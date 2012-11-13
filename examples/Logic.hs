{-# LANGUAGE GADTs, TypeFamilies, NoMonomorphismRestriction, RankNTypes,
    MultiParamTypeClasses, FlexibleInstances, OverlappingInstances,
    FlexibleContexts, TypeOperators, UndecidableInstances,
    QuasiQuotes
  #-}

import Control.Monad
import Control.Applicative

import PolyHandlers
import DesugarPolyHandlers


[operation|forall a.Failure ::        a|]
[operation|forall a.Choose  :: [a] -> a|]

infixr :-
data SomeList a = Last a | a :- SomeList a
  deriving Show

[operation|forall a.ChooseSome :: SomeList a -> a|]


type Logic a = ((h `Handles` Failure) (), (h `Handles` Choose) ()) => Comp h a

[handler|
  forward h.AllHandler a :: [a]
    handles {Failure, Choose} where
      Failure     k -> return []
      Choose l k -> do {xss <- mapM k l; return (join xss)}
      Return x   -> return [x]
|]
allResults :: Logic a -> Comp h [a] 
allResults comp = allHandler comp

[handler|
  forward h.MaybeHandler a :: Maybe a
    handles {Failure, Choose} where
      Failure  k -> return Nothing
      Choose xs k -> pickFirst xs
          where
            pickFirst []     = return Nothing
            pickFirst (x:xs) = do r <- k x
                                  case r of
                                    Just _  -> return r
                                    Nothing -> pickFirst xs
      -- Choose l k -> foldM (\m v ->
      --                          case m of
      --                            Just _  -> return m
      --                            Nothing -> k v) Nothing l
      Return x   -> return (Just x)
|]
maybeResults :: Logic a -> Comp h (Maybe a)
maybeResults comp = maybeHandler comp

data Stack h a = Stack ([Stack h a -> Comp h a])
[handler|
  forward h.(Handles h Failure Unit) => FirstHandler a :: Stack h a -> a
    handles {Failure, Choose} where
      Failure       k (Stack [])     -> failure
      Failure       k (Stack (x:xs)) -> x (Stack xs)
      Choose []     k (Stack [])     -> failure
      Choose []     k (Stack (x:xs)) -> x (Stack xs)
      Choose (a:as) k (Stack l)      -> k a (Stack (map k as ++ l))
      Return x        _              -> return x
|]
firstResult :: ((h `Handles` Failure) ()) => Logic a -> Comp h a
firstResult comp = firstHandler (Stack []) comp

[handler|
  IterativeHandler a :: Int -> (Bool, [a])
    handles {Failure, Choose} where
      Failure  k i -> (False, [])
      Choose l k i -> if i == 0 then (True, [])
                      else
                        let (bs, xss) = unzip (map (\x -> k x $! i-1) l) in
                        (any id bs, concat xss)
      Return x   i -> if i == 0 then (False, [x]) else (False, [])
|]
iterativeResults :: Logic a -> [[a]]
iterativeResults comp =
  foldr
    (\(b, xs) xss -> xs:(if b then xss else []))
    []
   (map (\i -> iterativeHandler i comp) [0..])

test1 :: Logic [Int]
test1 =
  do
    i <- choose [1..10]
    j <- choose [1..10]
    if (i+j) `mod` 2 == 0 then failure
      else return [i, j]

safeAddition :: [Int] -> Int -> Int -> Bool
safeAddition [] _ _ = True
safeAddition (r:rows) row i =
   row /= r &&
   abs (row - r) /= i &&
   safeAddition rows row (i + 1)

queens :: Int -> [[Int]]
queens n = foldM f [] [1..n] where
    f rows _ = [row : rows |
                row <- [1..n],
                safeAddition rows row 1]

check b = if b then return ()
          else failure

--queens :: Int -> [[Int]]
queens' n = foldM f [] [1..n] where
    f rows _ = do row <- choose [1..n]
                  check (safeAddition rows row 1)
                  return (row : rows)
