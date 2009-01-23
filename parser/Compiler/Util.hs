
module Compiler.Util(
    module Compiler.Util,
    module Control.Arrow,
    module Data.List, module Data.Char, module Data.Maybe
    ) where

import Control.Arrow
import Data.List
import Data.Maybe
import Data.Char


split :: Eq a => a -> [a] -> [[a]]
split y = rep $ second (drop 1) . break (== y)


rep :: ([a] -> (b, [a])) -> [a] -> [b]
rep f [] = []
rep f xs = b : rep f a
    where (b,a) = f xs
