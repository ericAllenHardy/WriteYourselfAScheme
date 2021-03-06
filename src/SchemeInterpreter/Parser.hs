module SchemeInterpreter.Parser (LispParser, parseExpr, readExpr, readLispFile) where

import           Control.Monad.Freer (Member, Eff)
import           SchemeInterpreter.LispComp (LispComp, throwError)
import           SchemeInterpreter.LispVal
import           Data.Char
import           Text.ParserCombinators.Parsec (Parser, alphaNum, anyChar, char
                                              , digit, endBy, letter, many
                                              , many1, noneOf, oneOf
                                              , optionMaybe, parse, sepBy, sepEndBy1
                                              , skipMany1, space, string, try
                                              , (<|>), newline)
import qualified Data.Vector as V

type LispParser = Parser LispVal

readExpr :: Member LispComp r => String -> Eff r LispVal
readExpr = readParser parseExpr

readLispFile :: Member LispComp r => String -> Eff r [LispVal]
readLispFile = readParser (parseExpr `sepEndBy1` newline)

readParser :: Member LispComp r => Parser a -> String -> Eff r a
readParser p input = case parse p "lisp" input of
  Left err  -> throwError (ParserError err)
  Right val -> return val

parseExpr :: LispParser
parseExpr = parseString
  <|> try parseBool
  <|> try parseChar
  <|> try parseFloat
  <|> try parseNumber
  <|> parseQuoted
  <|> parseClause
  <|> parseQuasiquote
  <|> try parseVector
  <|> parseAtom
  where
    parseClause = do
      char '('
      x <- try $ parseList <|> parseDottedList
      char ')'
      return x

parseString :: LispParser
parseString = do
  char '"'
  x <- many (parseEscape <|> noneOf "\\\"")
  char '"'
  return (String x)
  where
    parseEscape = char '\\' >> cLookup <$> anyChar

    cLookup 'n' = '\n'
    cLookup '\\' = '\\'
    cLookup 'r' = '\r'
    cLookup 't' = '\t'
    cLookup x = x

parseChar :: LispParser
parseChar = do
  string "#\\"
  c <- anyChar
  if isAlphaNum c
    then Char . maybe c cLookup <$> optionMaybe (many1 alphaNum)
    else return (Char c)
  where
    cLookup "space" = ' '
    cLookup "newline" = '\n'
    cLookup _ = error "huh? how'd you get here"

parseAtom :: LispParser
parseAtom = do
  first <- letter <|> symbol
  rest <- many (letter <|> digit <|> symbol)
  return $ Atom (first:rest)

parseBool :: LispParser
parseBool = do
  char '#'
  b <- oneOf "tf"
  return . Bool
    $ case b of
      't' -> True
      'f' -> False
      _   -> error "huh? how'd you get here"

parseNumber :: LispParser
parseNumber = parseDec1
  <|> try parseDec2
  <|> try parseBin
  <|> try parseOctal
  <|> try parseHex
  where
    parseDec1 = do
      x <- optionMaybe $ char '-'
      y <- many1 digit
      let f = case x of
            Just _  -> negate
            Nothing -> id
      return $ Number (f $ read y)

    parseDec2 = string "#d" >> Number . read <$> many1 digit

    parseSet :: String -> String -> (Integer -> Char -> Integer) -> LispParser
    parseSet k range readBase = do
      string k
      Number . foldl readBase 0 <$> many1 (oneOf range)

    parseBin = parseSet "#b" "01" readBin

    parseOctal = parseSet "#o" "01234567" readOct

    parseHex = parseSet "#x" "0123456789abcdefABCDEF" readHex

    readBin acc c = 2 * acc
      + case c of
        '1' -> 1
        '0' -> 0
        _   -> error "huh? how'd you get here"

    readOct acc c = 8 * acc + toInteger (digitToInt c)

    readHex acc c
      | c `elem` "0123456789" = 16 * acc + toInteger (digitToInt c)
      | otherwise = 16 * acc
        + case c of
          'a' -> 10
          'b' -> 11
          'c' -> 12
          'd' -> 13
          'e' -> 14
          'f' -> 15
          _   -> error "huh? how'd you get here"

parseFloat :: LispParser
parseFloat = parseDecimal <|> parseExponent
  where
    parseDecimal = do
      neg <- optionMaybe $ char '-'
      x <- many1 digit
      char '.'
      y <- many1 digit
      let absVal = read $ x ++ "." ++ y
      let f = case neg of
            Just _  -> negate
            Nothing -> id
      return $ Float (f absVal)

    parseExponent = do
      Float x <- parseDecimal
      char 'e'
      y <- many1 digit
      return (Float $ x * 10 ^ (read y :: Integer))

parseList :: LispParser
parseList = List <$> parseExpr `sepBy` spaces

parseDottedList :: LispParser
parseDottedList = do
  listHead <- endBy parseExpr spaces
  char '.'
  spaces
  DottedList listHead <$> parseExpr

parseQuoted :: LispParser
parseQuoted = do
  char '\''
  x <- parseExpr
  return (List [Atom "quote", x])

parseQuasiquote :: LispParser
parseQuasiquote = do
  string "`("
  xs <- (try parseQuoteSplice <|> parseUnquote <|> parseExpr) `sepBy ` spaces
  char ')'
  return (List [Atom "quasiquote", List xs])
  where
    parseUnquote = do
      char ','
      e <- parseExpr
      return (List [Atom "unquote", e])

    parseQuoteSplice = do
      string ",@"
      e <- parseExpr
      return (List [Atom "unquote-splicing", e])

parseVector :: LispParser
parseVector = do
  string "#("
  List x <- parseList
  char ')'
  return (Vector (V.fromList x))

symbol :: Parser Char
symbol = oneOf "!$%&|*+-/:<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space
