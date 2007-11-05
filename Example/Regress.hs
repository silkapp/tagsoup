module Example.Regress (
    regress
   ) where

import Text.HTML.TagSoup
import qualified Text.HTML.TagSoup.Match as Match
import Control.Exception

-- * The Test Monad

data Test a = Pass
instance Monad Test where
    a >> b = a `seq` b
instance Show (Test a) where
    show x = x `seq` "All tests passed"
pass :: Test ()
pass = Pass
a === b = if a == b then pass else fail $ "Does not equal: " ++ show a ++ " =/= " ++ show b

-- * The Main section

regress :: IO ()
regress = print $ do
    parseTests
    lazyTags == lazyTags `seq` pass
    matchCombinators


{- |
This routine tests the laziness of the TagSoup parser.
For each critical part of the parser we provide a test input
with a token of infinite size.
Then the output must be infinite too.
If the laziness is broken, then the output will stop early.
We collect the thousandth character of the output of each test case.
If computation of the list stops somewhere,
you have found a laziness stopper.
-}


lazyTags :: [Char]
lazyTags =
   map ((!!1000) . show . parseTags) $
      (cycle "Rhabarber") :
      (repeat '&') :
      ("<"++cycle "html") :
      ("<html "++cycle "na!me=value ") :
      ("<html name="++cycle "value") :
      ("<html name=\""++cycle "value") :
      ("<html name="++cycle "val!ue") :
      ("<html "++cycle "name") :
      ("</"++cycle "html") :
      ("<!-- "++cycle "comment") :
      ("<!"++cycle "doctype") :
      ("<!DOCTYPE"++cycle " description") :
      (cycle "1<2 ") :
      
      -- need further analysis
      ("<html name="++cycle "val&ue") :
      ("<html name="++cycle "va&l!ue") :
      ("&" ++ cycle "t") :

      -- i don't see how this can work unless the junk gets into the AST?
      --("</html "++cycle "junk") :

      []



matchCombinators :: Test ()
matchCombinators = assert (and tests) pass
    where
        tests =
            Match.tagText (const True) (TagText "test") :
            Match.tagText ("test"==) (TagText "test") :
            Match.tagText ("soup"/=) (TagText "test") :
            Match.tagOpenNameLit "table"
               (TagOpen "table" [("id", "name")]) :
            Match.tagOpenLit "table" (Match.anyAttrLit ("id", "name"))
               (TagOpen "table" [("id", "name")]) :
            Match.tagOpenLit "table" (Match.anyAttrNameLit "id")
               (TagOpen "table" [("id", "name")]) :
            not (Match.tagOpenLit "table" (Match.anyAttrLit ("id", "name"))
                  (TagOpen "table" [("id", "other name")])) :
            []


parseTests :: Test ()
parseTests = do
    parseTags "<!DOCTYPE TEST>" === [TagOpen "!DOCTYPE" [("TEST","")]]
    parseTags "<test \"foo bar\">" === [TagOpen "test" [("","foo bar")]]
    parseTags "<test \'foo bar\'>" === [TagOpen "test" [("","foo bar")]]
    parseTags "hello &amp; world" === [TagText "hello & world"]
    parseTags "hello &#64; world" === [TagText "hello @ world"]
    parseTags "hello &haskell; world" === [TagText "hello &haskell; world"]

    parseTags "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">" ===
        [TagOpen "!DOCTYPE" [("HTML",""),("PUBLIC",""),("","-//W3C//DTD HTML 4.01//EN"),("","http://www.w3.org/TR/html4/strict.dtd")]]
    parseTags "<script src=\"http://edge.jobthread.com/feeds/jobroll/?s_user_id=100540&subtype=slashdot\">" ===
        [TagOpen "script" [("src","http://edge.jobthread.com/feeds/jobroll/?s_user_id=100540&subtype=slashdot")]]
