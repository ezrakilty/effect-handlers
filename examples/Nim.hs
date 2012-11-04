-- The subtraction game (a variant of the game of nim).
--
-- A game begins with n sticks on the table. I go first. I take
-- between one and three sticks, then it is your turn, and you take
-- between one and three sticks. We alternate turns until we run out
-- of sticks. The winner is the player who takes the last stick.

{-# LANGUAGE TypeFamilies, NoMonomorphismRestriction,
             FlexibleContexts, TypeOperators,
             FlexibleInstances, MultiParamTypeClasses, OverlappingInstances,
             TemplateHaskell, QuasiQuotes
  #-}

import Data.List
import Handlers
import DesugarHandlers

-- Operations:
--
--   choose (player, n) = m, if player chooses m out of the remaining n sticks

data Player = Me | You
  deriving (Show, Eq)

-- The 'Move' operation represents a move by a player in the game. The
-- parameter is a pair of the player and the number of sticks
-- remaining. The return value is the number of sticks the player
-- chooses to take.
[operation|Move :: Player -> Int -> Int|]

-- a game parameterised by the number of starting sticks
game :: (h `Handles` Move) => Int -> Comp h Player
game = myTurn

myTurn n =
  if n == 0 then return You
  else
    do
      take <- move Me n
      yourTurn (n-take)
      
yourTurn n =
  if n == 0 then return Me
  else
    do
      take <- move You n
      myTurn (n-take)

-- Note that this implementation does not check that each player takes
-- between one and three sticks on each turn. We will add such a check
-- later.

-- a perfect strategy given n remaining sticks (represented as an
-- operation clause)
perfect :: Int -> (Int -> r) -> r
perfect n k = k (max (n `mod` 4) 1)

-- perfect vs perfect
[handler|
  PP :: Player handles {Move} where
    Return x   -> x
    Move _ n k -> perfect n k
|]
pp :: Int -> Player
pp n = pP (game n)

-- *Main> pp 3
-- Me
-- *Main> pp 29
-- Me
-- *Main> pp 32
-- You

-- list of valid moves given n sticks remaining
validMoves :: Int -> [Int]
validMoves n = filter (<= n) [1,2,3]

-- a brute force strategy
--
-- Enumerate all the moves. If one of them leads to a win for player,
-- then move it. Otherwise just take 1 stick.
bruteForce :: Player -> Int -> (Int -> Player) -> Player
bruteForce player n k =
  let winners = map k (validMoves n) in
  case (elemIndex player winners) of
    Nothing -> k 1
    Just i  -> k (i+1)

-- brute force vs perfect
[handler|
  BP :: Player handles {Move} where
    Return x     -> x
    Move Me  n k -> bruteForce Me n k
    Move You n k -> perfect n k
|]
bp :: Int -> Player
bp n = bP (game n)

-- bruteForce behaves just the same as the perfect strategy, except it
-- is much slower

-- *Main> bp 3
-- Me
-- *Main> bp 31
-- Me
-- *Main> bp 32
-- You

-- Instead of simply evaluating the winner according to some strategy,
-- we can also compute other data. For instance, we can compute a tree
-- representing the possible moves of each player.

-- a tree encoding possible moves
data MoveTree = Take (Player, [(Int, MoveTree)]) | Winner Player
  deriving Show

-- reify a move as part of a move tree
reifyMove :: Player -> Int -> (Int -> Comp h MoveTree) -> Comp h MoveTree
reifyMove player n k =
  do
    l <- mapM k (validMoves n)
    return $ Take (player, zip [1..] l)
    
-- generate the complete move tree for a game starting with n sticks
[handler|
  forward h.MM :: MoveTree handles {Move} where
    Return x        -> return (Winner x)
    Move player n k -> reifyMove player n k
|] 
mm :: Int -> MoveTree
mm n = handlePure (mM (game n))
    
-- *Main> mm 3
-- Take (Me, [(1, Take (You, [(1, Take (Me, [(1,Winner Me)])),
--                            (2, Winner You)])),
--            (2, Take (You, [(1,Winner You)])),
--            (3, Winner Me)])

-- generate the move tree for a game in which you play a perfect
-- strategy

[handler|
  forward h.(h `Handles` Move) =>
    MPIn :: MoveTree handles {Move} where
      Return x        -> return (Winner x)
      Move player n k -> case player of
                           Me  -> reifyMove Me n k
                           You ->
                             do
                               take <- move You n
                               tree <- k take
                               return $ Take (You, [(take, tree)])
|]
[handler|
  MP :: MoveTree handles {Move} where
    Return x     -> x
    Move You n k -> perfect n k
|]
mp :: Int -> MoveTree
mp n = (mP . mPIn) (game n)

-- *Main> mp 3
-- Take (Me, [(1, Take (You, [(2, Winner You)])),
--            (2, Take (You, [(1, Winner You)])),
--            (3, Winner Me)])
   
-- cheat (p, m) is invoked when player p cheats by attempting to take
-- m sticks (for m < 1 or 3 < m)
[operation|forall a.Cheat :: Player -> Int -> a|]

-- a checked choice
--
-- If the player chooses a valid number of sticks, then the game
-- continues. If not, then the cheat operation is invoked.
checkChoice :: (h `Handles` Move, h `PolyHandles` Cheat) =>
               Player -> Int -> (Int -> Comp h a) -> Comp h a
checkChoice player n k =
  do
    take <- move player n
    if take < 0 || 3 < take then cheat player take
    else k take

-- a game that checks for cheating
[handler|
  forward h.(h `Handles` Move, h `PolyHandles` Cheat) =>
    Check :: Player handles {Move} where
      Return x        -> return x
      Move player n k -> checkChoice player n k
|]
checkedGame :: (h `Handles` Move, h `PolyHandles` Cheat) => Int -> Comp h Player  
checkedGame n = check (game n)

-- a cheating strategy: take all of the sticks, no matter how many
-- remain
cheater n k = k n

-- I cheat against your perfect strategy
-- (I always win)
[handler|
  CP :: Player handles {Move} where
    Return x     -> x
    Move Me  n k -> cheater n k
    Move You n k -> perfect n k
|]
cp :: Int -> Player
cp n = cP (game n)

-- *Main> cp 32
-- Me

-- a game in which cheating leads to the game being abandoned, and the
-- cheater is reported along with how many sticks they attempted to
-- take
[handler|
  forward h.CheatEnd :: Player polyhandles {Cheat} where
    Return x         -> return x
    Cheat player n k -> error ("Cheater: " ++ show player ++ ", took; " ++ show n)
|]
cheaterEndingGame :: (h `Handles` Move) => Int -> Comp h Player
cheaterEndingGame n = cheatEnd (checkedGame n)

-- a game in which if I cheat then you win immediately, and if you
-- cheat then I win immediately
[handler|
  forward h.CheatLose :: Player polyhandles {Cheat} where
    Return x      -> return x
    Cheat Me n k  -> return You
    Cheat You n k -> return Me   
|]
cheaterLosingGame :: (h `Handles` Move) => Int -> Comp h Player
cheaterLosingGame n = cheatLose (checkedGame n)

-- I cheat against your perfect strategy
--
-- (If n < 4 then I win, otherwise the game is abandoned because I
-- cheat.)
cpEnding :: Int -> Player
cpEnding n = cP (cheaterEndingGame n)

-- *Main> cpEnding 3
-- Me
-- *Main> cpEnding 5
-- *** Exception: Cheater: Me, took: 5

-- I cheat against your perfect strategy
--
-- (If n < 4 then I win, otherwise you win because I cheat.)
cpLosing :: Int -> Player
cpLosing n = cP (cheaterLosingGame n)

-- *Main> cpLosing 3
-- Me
-- *Main> cpLosing 5
-- You
