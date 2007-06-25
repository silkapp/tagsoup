
module Text.HTML.TagSoup.Parser(parseTags) where

import Text.HTML.TagSoup.Type
import Text.HTML.TagSoup.Position
import Control.Monad.State
import Data.Char
import Data.List


---------------------------------------------------------------------
-- * Driver

parseTags :: CharType char => String -> [Tag char]
parseTags x = {- mergeTexts $ -} evalState parse (x,initialize "")


mergeTexts (TagText x:xs) = TagText (concat $ x:texts) : warns ++ mergeTexts rest
    where
        (texts,warns,rest) = f xs
    
        f (TagText x:xs) = (x:a,b,c)
            where (a,b,c) = f xs
        f (TagWarning x:xs) = (a,TagWarning x:b,c)
            where (a,b,c) = f xs
        f xs = ([],[],xs)

mergeTexts (x:xs) = x : mergeTexts xs
mergeTexts [] = []


---------------------------------------------------------------------
-- * Combinators


type Parser a = State (String,Position) a


isNameChar x = isAlphaNum x || x `elem` "-_:"

consume :: Int -> Parser ()
consume n = do
    ~(s,p) <- get
    let (a,b) = splitAt n s
    put (b, updateOnString p a)


breakOn :: String -> Parser (String,Bool)
breakOn end = do
    ~(s,p) <- get
    if null s then
        return ("",True)
     else if end `isPrefixOf` s then
        consume (length end) >> return ("",False)
     else do
        consume 1
        ~(a,b) <- breakOn end
        return (head s:a,b)


breakName :: Parser String
breakName = do
    ~(s,p) <- get
    if not (null s) && isAlpha (head s) then do
        let (a,b) = span isNameChar s
        consume (length a)
        return a
     else
        return ""

breakNumber :: Parser (Maybe Int)
breakNumber = do
    ~(s,p) <- get
    if not (null s) && isDigit (head s) then do
        let (a,b) = span isDigit s
        consume (length a)
        return $ Just $ read a
     else
        return Nothing


dropSpaces :: Parser ()
dropSpaces = do
    ~(s,p) <- get
    let n = length $ takeWhile isSpace s
    consume n


tagPos :: CharType char => Position -> Tag char -> Tag char
tagPos _ x = x


---------------------------------------------------------------------
-- * Parser

parse :: CharType char => Parser [Tag char]
parse = do
    ~(s,p) <- get
    case s of
        '<':'!':'-':'-':_ -> consume 4 >> comment p
        '<':'!':_         -> consume 2 >> special p
        '<':'/':_         -> consume 2 >> close p
        '<':_             -> consume 1 >> open p
        []                -> return []
        '&':_             -> do
            consume 1
            ~(s,warn) <- entity p
            rest <- parse
            return $ tagPos p (TagText s) : rest
        s:ss              -> do
            consume 1
            rest <- parse
            return $ tagPos p (TagText [fromHTMLChar $ Char s]) : rest


comment p1 = do
    ~(inner,bad) <- breakOn "-->"
    rest <- parse
    return $ tagPos p1 (TagComment inner) :
             [tagPos p1 $ TagWarning "Unexpected end when looking for \"-->\"" | bad] ++
             rest


special p1 = do
    name <- breakName
    dropSpaces
    ~(inner,bad) <- breakOn ">"
    rest <- parse
    return $ tagPos p1 (TagSpecial name inner) :
             [tagPos p1 $ TagWarning "Empty name in special" | null name] ++
             [tagPos p1 $ TagWarning "Unexpected end when looking for \">\"" | bad] ++
             rest


close p1 = do
    name <- breakName
    dropSpaces
    ~(s,p) <- get
    case s of
        '>':s -> do
            consume 1
            rest <- parse
            return $ tagPos p1 (TagClose name) :
                     [tagPos p1 $ TagWarning "Empty name in close tag" | null name] ++
                     rest
        _ -> do
            ~(_,bad) <- breakOn ">"
            rest <- parse
            return $ tagPos p1 (TagClose name) :
                     (tagPos p1 $ TagWarning $ if bad then "Unexpected end when looking for \">\""
                                                      else "Junk in closing tag") :
                     rest


open p1 = do
    name <- breakName
    if null name then do
        rest <- parse
        return $ tagPos p1 (TagText [fromHTMLChar $ Char '<']) : rest
     else do
        ~(atts,shut,warns) <- attribs p1
        rest <- parse
        return $ tagPos p1 (TagOpen name atts) :
                 [tagPos p1 (TagClose name) | shut] ++
                 warns ++ rest


attribs :: CharType char => Position -> Parser ([Attribute char],Bool,[Tag char])
attribs p1 = do
    dropSpaces
    ~(s,p) <- get
    case s of
        '/':'>':_ -> consume 2 >> return ([],True ,[])
        '>':_     -> consume 1 >> return ([],False,[])
        []        -> return ([],False,[tagPos p1 $ TagWarning "Unexpected end when looking for \">\""])
        _ -> attrib p1


attrib :: CharType char => Position -> Parser ([Attribute char],Bool,[Tag char])
attrib p1 = do
    name <- breakName
    if null name then do
        consume 1
        ~(atts,shut,warns) <- attribs p1
        return (atts,shut,tagPos p1 (TagWarning "Junk character in tag") : warns)
     else do
        ~(s,p) <- get
        case s of
            '=':s -> do
                consume 1
                ~(val,warns1) <- value
                ~(atts,shut,warns2) <- attribs p1
                return ((name,val):atts,shut,warns1++warns2)
            _ -> do
                ~(atts,shut,warns) <- attribs p1
                return ((name,[]):atts,shut,warns)


value :: CharType char => Parser ([char],[Tag char])
value = do
    ~(s,p) <- get
    case s of
        '\"':ss -> consume 1 >> f p True "\""
        '\'':ss -> consume 1 >> f p True "\'"
        _ -> f p False " />"
    where
        f p1 quote end = do
            ~(s,p) <- get
            case s of
                '&':_ -> do
                    consume 1
                    ~(cs1,warns1) <- entity p
                    ~(cs2,warns2) <- f p1 quote end
                    return (cs1++cs2,warns1++warns2)
                c:_ | c `elem` end -> do
                    if quote then consume 1 else return ()
                    return ([],[])
                c:_ -> do
                    consume 1
                    ~(cs,warns) <- f p1 quote end
                    return (fromHTMLChar (Char c):cs,warns)
                [] -> return ([],[tagPos p1 $ TagWarning "Unexpected end in attibute value"])


entity :: CharType char => Position -> Parser ([char],[Tag char])
entity p1 = do
    ~(s,p) <- get
    ~(res,bad) <- case s of
        '#':_ -> do
            consume 1
            num <- breakNumber
            case num of
                Nothing -> return ([Char '&',Char '#'],True)
                Just y -> return ([NumericRef y],False)
        _ -> do
            name <- breakName
            if null name then
                return ([Char '&'],True)
             else
                return ([NamedRef name], False)
    if bad then
        return (map fromHTMLChar res,[tagPos p1 $ TagWarning "Unquoted & found"])
     else do
        ~(s,p) <- get
        case s of
            ';':_ -> consume 1 >> return (map fromHTMLChar res,[])
            _ -> return (map fromHTMLChar res,[tagPos p1 $ TagWarning "Missing closing \";\" in entity"])
