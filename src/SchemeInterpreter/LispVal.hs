module SchemeInterpreter.LispVal
    ( LispVal(..)
    , LispError(..)
    , FuncApplication(..)
    , LispFunction) where

import qualified Data.Vector as V
import           Text.ParserCombinators.Parsec (ParseError)

data LispVal = Atom String
             | Char Char
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | Float Float
             | String String
             | Bool Bool
             | Vector (V.Vector LispVal)
  deriving (Eq)

type LispFunction = [LispVal] -> FuncApplication LispVal

instance Show LispVal where
  show (Atom atom) = atom
  show (Char c) = "#\\" ++ [c]
  show (List ls) = "(" ++ showLs ls ++ ")"
  show (DottedList listHead listTail) =
    "(" ++ showLs listHead ++ " . " ++ show listTail ++ ")"
  show (Number n) = show n
  show (Float x) = show x
  show (String s) = show s
  show (Bool True) = "#t"
  show (Bool False) = "#f"
  show (Vector ls) = "#(" ++ showLs (V.toList ls) ++ ")"

showLs :: [LispVal] -> String
showLs = unwords . map show

data LispError = NumArgs Integer [LispVal]
               | NumArgsRange Integer Integer [LispVal]
               | ValueError String LispVal
               | TypeMismatch String LispVal
               | ParserError ParseError
               | BadSpecialForm String LispVal
               | NotFunction String String
               | UnboundVar String String
  deriving (Eq)

instance Show LispError where
  show (UnboundVar message varname) = message ++ ": " ++ varname
  show (BadSpecialForm message form) = message ++ ": " ++ show form
  show (NotFunction message func) = message ++ ": " ++ show func
  show (ValueError msg found) = msg ++ ": " ++ show found
  show (NumArgs expected found) =
    "Expected " ++ show expected ++ " args; found values " ++ showLs found
  show (NumArgsRange minCount maxCount found) = "Expected between "
    ++ show minCount
    ++ " and "
    ++ show maxCount
    ++ " args; found values "
    ++ showLs found
  show (TypeMismatch expected found) =
    "Invalid type: expected " ++ expected ++ ", found " ++ show found
  show (ParserError parseErr) = "Parse error at " ++ show parseErr

data FuncApplication a = FAValue a
                       | FAError LispError
  deriving (Functor)

instance Applicative FuncApplication where
  pure = FAValue

  f <*> x = case x of
    FAError e  -> FAError e
    FAValue x' -> case f of
      FAError e  -> FAError e
      FAValue f' -> FAValue (f' x')