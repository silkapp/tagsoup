
module Compiler.Optimise where

import Compiler.Type2
import Compiler.Util


optimise :: Program -> Program
optimise = deadCode . specialise


---------------------------------------------------------------------
-- Remove rules that are unreachable from root

deadCode :: Program -> Program
deadCode = id


---------------------------------------------------------------------
-- Given parameter invokations of local rules, specialise them

type Template = (String, [Maybe String])

specialise :: Program -> Program
specialise x = useTemplate ts $ x ++ map (genTemplate x) ts
    where
        ts = zipWith (\i x -> (x, fst x ++ show i)) [1..] $
             nub $ mapMaybe getTemplate $ childrenBi x


getTemplate :: Exp -> Maybe Template
getTemplate (Call name xs) | any isJust ys = Just (name,ys)
    where ys = map asLit xs
getTemplate _ = Nothing


useTemplate :: [(Template, String)] -> Program -> Program
useTemplate ts = transformBi f
    where
        f x@(Call _ args) = case getTemplate x of
            Just y -> Call (fromJust $ lookup y ts) (filter (isNothing . asLit) args)
            _ -> x
        f x = x


genTemplate :: [Rule] -> (Template,String) -> Rule
genTemplate xs ((name,args),name2) = Rule name2 args2 bod2
    where
        Rule _ as bod = fromJust $ find ((==) name . ruleName) xs
        args2 = concat $ zipWith (\i s -> [s | isNothing i]) args as
        rep = concat $ zipWith (\i s -> [(s,Lit $ fromJust i) | isJust i]) args as
        bod2 = transformBi f bod
        f (Var x) = fromMaybe (Var x) $ lookup x rep
        f x = x
