-- | The central type in TagSoup

module Text.HTML.TagSoup.Type(
    -- * Data structures and parsing
    Tag(..), Attribute, Row, Column,
    
    -- * Position manipulation
    Position, tagPosition, nullPosition, positionChar, positionString,

    -- * Tag identification
    isTagOpen, isTagClose, isTagText, isTagWarning,
    isTagOpenName, isTagCloseName,

    -- * Extraction
    fromTagText, fromAttrib,
    maybeTagText, maybeTagWarning,
    innerText,
    ) where


import Data.Char
import Data.List
import Data.Maybe
import Text.StringLike as Str


-- | An HTML attribute @id=\"name\"@ generates @(\"id\",\"name\")@
type Attribute str = (str,str)

type Row = Int
type Column = Int


--- All positions are stored as a row and a column, with (1,1) being the
--- top-left position

data Position = Position !Row !Column deriving Show

nullPosition = (Position 1 1)

positionString :: Position -> String -> Position
positionString = foldl' positionChar

positionChar :: Position -> Char -> Position
positionChar (Position r c) x = case x of
    '\n' -> Position (r+1) c
    '\t' -> Position r (c + 8 - mod (c-1) 8)
    _    -> Position r (c+1)

tagPosition :: Position -> Tag str
tagPosition (Position r c) = TagPosition r c


-- | An HTML element, a document is @[Tag]@.
--   There is no requirement for 'TagOpen' and 'TagClose' to match
data Tag str =
     TagOpen str [Attribute str]  -- ^ An open tag with 'Attribute's in their original order.
   | TagClose str                 -- ^ A closing tag
   | TagText str                  -- ^ A text node, guaranteed not to be the empty string
   | TagComment str               -- ^ A comment
   | TagCData str                 -- ^ CData text
   | TagWarning str               -- ^ Meta: Mark a syntax error in the input file
   | TagPosition !Row !Column     -- ^ Meta: The position of a parsed element
     deriving (Show, Eq, Ord)


-- | Test if a 'Tag' is a 'TagOpen'
isTagOpen :: Tag str -> Bool
isTagOpen (TagOpen {})  = True; isTagOpen  _ = False

-- | Test if a 'Tag' is a 'TagClose'
isTagClose :: Tag str -> Bool
isTagClose (TagClose {}) = True; isTagClose _ = False

-- | Test if a 'Tag' is a 'TagText'
isTagText :: Tag str -> Bool
isTagText (TagText {})  = True; isTagText  _ = False

-- | Extract the string from within 'TagText', otherwise 'Nothing'
maybeTagText :: Tag str -> Maybe str
maybeTagText (TagText x) = Just x
maybeTagText _ = Nothing

-- | Extract the string from within 'TagText', crashes if not a 'TagText'
fromTagText :: Show str => Tag str -> str
fromTagText (TagText x) = x
fromTagText x = error $ "(" ++ show x ++ ") is not a TagText"

-- | Extract all text content from tags (similar to Verbatim found in HaXml)
innerText :: StringLike str => [Tag str] -> str
innerText = Str.concat . mapMaybe maybeTagText

-- | Test if a 'Tag' is a 'TagWarning'
isTagWarning :: Tag str -> Bool
isTagWarning (TagWarning {})  = True; isTagWarning _ = False

-- | Extract the string from within 'TagWarning', otherwise 'Nothing'
maybeTagWarning :: Tag str -> Maybe str
maybeTagWarning (TagWarning x) = Just x
maybeTagWarning _ = Nothing

-- | Extract an attribute, crashes if not a 'TagOpen'.
--   Returns @\"\"@ if no attribute present.
fromAttrib :: (Show str, Eq str, StringLike str) => str -> Tag str -> str
fromAttrib att (TagOpen _ atts) = fromMaybe Str.empty $ lookup att atts
fromAttrib _ x = error ("(" ++ show x ++ ") is not a TagOpen")


-- | Returns True if the 'Tag' is 'TagOpen' and matches the given name
isTagOpenName :: Eq str => str -> Tag str -> Bool
isTagOpenName name (TagOpen n _) = n == name
isTagOpenName _ _ = False

-- | Returns True if the 'Tag' is 'TagClose' and matches the given name
isTagCloseName :: Eq str => str -> Tag str -> Bool
isTagCloseName name (TagClose n) = n == name
isTagCloseName _ _ = False
