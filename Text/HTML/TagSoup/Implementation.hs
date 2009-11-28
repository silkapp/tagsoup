{-# LANGUAGE RecordWildCards, PatternGuards, ScopedTypeVariables #-}

module Text.HTML.TagSoup.Implementation where

import Data.List
import Text.HTML.TagSoup.Type
import Text.HTML.TagSoup.Options
import Text.StringLike as Str
import Numeric
import Data.Char
import Control.Exception(assert)
import Control.Arrow

---------------------------------------------------------------------
-- BOTTOM LAYER

data Out
    = Char Char
    | Tag          -- <
    | TagShut      -- </
    | AttName
    | AttVal
    | TagEnd       -- >
    | TagEndClose  -- />
    | Comment      -- <!--
    | CommentEnd   -- -->
    | Entity       -- &
    | EntityNum    -- &#
    | EntityHex    -- &#x
    | EntityEnd    -- ;
    | EntityEndAtt -- missing the ; and in an attribute
    | Warn String
    | Pos Position
      deriving (Show,Eq)

errSeen x = Warn $ "Unexpected " ++ show x
errWant x = Warn $ "Expected " ++ show x

data S = S
    {s :: S
    ,tl :: S
    ,hd :: Char
    ,eof :: Bool
    ,next :: String -> Maybe S
    ,pos :: [Out] -> [Out]
    }


expand :: Position -> String -> S
expand p text = res
    where res = S{s = res
                 ,tl = expand (positionChar p (head text)) (tail text)
                 ,hd = if null text then '\0' else head text
                 ,eof = null text
                 ,next = next p text
                 ,pos = (Pos p:)
                 }

          next p (t:ext) (s:tr) | t == s = next (positionChar p t) ext tr
          next p text [] = Just $ expand p text
          next _ _ _ = Nothing

infixr &
(&) :: Outable a => a -> [Out] -> [Out]
(&) x xs = outable x : xs

class Outable a where outable :: a -> Out
instance Outable Char where outable = Char
instance Outable Out where outable = id


state :: String -> S
state s = expand nullPosition s

---------------------------------------------------------------------
-- TOP LAYER


output :: forall str . StringLike str => ParseOptions str -> [Out] -> [Tag str]
output ParseOptions{..} x = (if optTagTextMerge then tagTextMerge else id) $ f ((nullPosition,[]),x)
    where
        -- main choice loop
        f :: ((Position,[Tag str]),[Out]) -> [Tag str]
        f ((p,ws),xs) | p `seq` False = [] -- otherwise p is a space leak when optTagPosition == False
        f ((p,ws),xs) | not $ null ws = (if optTagWarning then (reverse ws++) else id) $ f ((p,[]),xs)
        f ((p,ws),Pos p2:xs) = f ((p2,ws),xs)

        f x | isChar x = pos x $ TagText a : f y
            where (y,a) = charsStr x
        f x | isTag x = pos x $ TagOpen a b : (if isTagEndClose z then pos x $ TagClose a : f (next z) else f (skip isTagEnd z))
            where (y,a) = charsStr $ next x
                  (z,b) = atts y
        f x | isTagShut x = pos x $ (TagClose a:) $
                (if not (null b) then warn x "Unexpected attributes in close tag" else id) $
                if isTagEndClose z then warn x "Unexpected self-closing in close tag" $ f (next z) else f (skip isTagEnd z)
            where (y,a) = charsStr $ next x
                  (z,b) = atts y
        f x | isComment x = pos x $ TagComment a : f (skip isCommentEnd y)
            where (y,a) = charsStr $ next x
        f x | isEntity x = poss x ((if optTagWarning then id else filter (not . isTagWarning)) $ optEntityData a) ++ f (skip isEntityEnd y) 
            where (y,a) = charsStr $ next x
        f x | isEntityChr x = pos x $ TagText (fromChar $ entityChr x a) : f (skip isEntityEnd y)
            where (y,a) = chars $ next x
        f x | Just a <- fromWarn x = if optTagWarning then pos x $ TagWarning (fromString a) : f (next x) else f (next x)
        f x | isEof x = []

        atts x | isAttName x = second ((a,b):) $ atts z
            where (y,a) = charsStr (next x)
                  (z,b) = if isAttVal y then charsEntsStr (next y) else (y, empty)
        atts x | isAttVal x = second ((empty,a):) $ atts y
            where (y,a) = charsEntsStr (next x)
        atts x = (x, [])

        -- chars
        chars = charss False
        charsStr = (id *** fromString) .  chars
        charsEntsStr = (id *** fromString) .  charss True

        -- loop round collecting characters, if the b is set including entity
        charss t x | Just a <- fromChr x = (y, a:b)
            where (y,b) = charss t (next x)
        charss t x | t, isEntity x = second (toString n ++) $ charss t $ addWarns m z
            where (y,a) = charsStr $ next x
                  (z,b) = (if b then skip isEntityEnd y else next y, not $ isEntityEndAtt y)
                  (n,m) = optEntityAttrib (a,b)
        charss t x | t, isEntityChr x = second (entityChr x a:) $ charss t z
            where (y,a) = chars $ next x
                  (z,b) = charss t $ if isEntityEnd y then next y else skip isEntityEndAtt y
        charss t ((_,w),Pos p:xs) = charss t ((p,w),xs)
        charss t x | Just a <- fromWarn x = charss t $ (if optTagWarning then addWarns [TagWarning $ fromString a] else id) $ next x
        charss t x = (x, [])

        -- utility functions
        next = second (drop 1)
        skip f x = assert (isEof x || f x) (next x)
        addWarns ws x@((p,w),y) = ((p, reverse (poss x ws) ++ w), y)
        pos ((p,_),_) rest = if optTagPosition then tagPosition p : rest else rest
        warn x s rest = if optTagWarning then pos x $ TagWarning (fromString s) : rest else rest
        poss x = concatMap (\w -> pos x [w]) 


entityChr x s | isEntityNum x = chr $ read s
              | isEntityHex x = chr $ fst $ head $ readHex s


isEof (_,[]) = True; isEof _ = False
isChar (_,Char{}:_) = True; isChar _ = False
isTag (_,Tag{}:_) = True; isTag _ = False
isTagShut (_,TagShut{}:_) = True; isTagShut _ = False
isAttName (_,AttName{}:_) = True; isAttName _ = False
isAttVal (_,AttVal{}:_) = True; isAttVal _ = False
isTagEnd (_,TagEnd{}:_) = True; isTagEnd _ = False
isTagEndClose (_,TagEndClose{}:_) = True; isTagEndClose _ = False
isComment (_,Comment{}:_) = True; isComment _ = False
isCommentEnd (_,CommentEnd{}:_) = True; isCommentEnd _ = False
isEntity (_,Entity{}:_) = True; isEntity _ = False
isEntityChr (_,EntityNum{}:_) = True; isEntityChr (_,EntityHex{}:_) = True; isEntityChr _ = False
isEntityNum (_,EntityNum{}:_) = True; isEntityNum _ = False
isEntityHex (_,EntityHex{}:_) = True; isEntityHex _ = False
isEntityEnd (_,EntityEnd{}:_) = True; isEntityEnd _ = False
isEntityEndAtt (_,EntityEndAtt{}:_) = True; isEntityEndAtt _ = False
isWarn (_,Warn{}:_) = True; isWarn _ = False

fromChr (_,Char x:_) = Just x ; fromChr _ = Nothing
fromWarn (_,Warn x:_) = Just x ; fromWarn _ = Nothing


-- Merge all adjacent TagText bits
tagTextMerge :: StringLike str => [Tag str] -> [Tag str]
tagTextMerge (TagText x:xs) = TagText (strConcat (x:a)) : tagTextMerge b
    where
        (a,b) = f xs

        f (TagText x:xs) = (x:a,b)
            where (a,b) = f xs
        f (TagPosition{}:x@TagText{}:xs) = f $ x : xs
        f x = g x id x

        g o op (p@TagPosition{}:w@TagWarning{}:xs) = g o (op . (p:) . (w:)) xs
        g o op (w@TagWarning{}:xs) = g o (op . (w:)) xs
        g o op (p@TagPosition{}:x@TagText{}:xs) = f $ p : x : op xs
        g o op (x@TagText{}:xs) = f $ x : op xs
        g o op _ = ([], o)

tagTextMerge (x:xs) = x : tagTextMerge xs
tagTextMerge [] = []
