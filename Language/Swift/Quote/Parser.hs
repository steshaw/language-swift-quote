{-# LANGUAGE FlexibleContexts #-}

module Language.Swift.Quote.Parser where

import Language.Swift.Quote.Syntax

import Control.Applicative
import Control.Monad
import Control.Monad.Identity
import Control.Arrow (left)
import Data.Maybe
import Data.Text
import Debug.Trace
import qualified Text.ParserCombinators.Parsec as P
import Text.Parsec.Text (Parser)
import Text.Parsec (try)
import qualified Text.Parsec.Language as L
import qualified Text.Parsec.Token as T

parseIt :: Parser a -> Text -> Either String a
parseIt p input = left show (P.parse (ws *> p <* ws) "<stdin>" input)

parse :: Text -> Either String Module
parse = parseIt module_

parseExpression :: Text -> Either String Expression
parseExpression = parseIt expression

parseDeclaration :: Text -> Either String Declaration
parseDeclaration = parseIt declaration

parseFunctionCall :: Text -> Either String FunctionCall
parseFunctionCall = parseIt functionCallExpression

parseInitializer :: Text -> Either String PostfixExpression
parseInitializer = parseIt initializerExpression

initializerExpression :: Parser PostfixExpression
initializerExpression = do
  pfe <- postfixExpression
  _ <- op "."
  postfixInitTail pfe

module_ :: Parser Module
module_ = do
  topDecls <- topLevelDeclaration
  _ <- P.eof
  return $ Module topDecls

------------------------------------------------------------
-- Auxiliary
------------------------------------------------------------

notice :: String -> String
notice msg = "\n\n\n" ++ msg ++ "\n\n\n"

traceVar :: Show a => String -> a -> Parser ()
traceVar n v = trace (notice n ++ " = " ++ show v) $ pure ()

------------------------------------------------------------
-- Auxiliary lexical functions
------------------------------------------------------------

reservedWordsDeclarations :: [String]
reservedWordsDeclarations =
 [ "class"
 , "deinit"
 , "enum"
 , "extension"
 , "func"
 , "import"
 , "init"
 , "inout"
 , "internal"
 , "let"
 , "operator"
 , "private"
 , "protocol"
 , "public"
 , "static"
 , "struct"
 , "subscript"
 , "typealias"
 , "var"
 ]

reservedWordsStatements :: [String]
reservedWordsStatements =
  [ "break"
  , "case"
  , "continue"
  , "default"
  , "defer"
  , "do"
  , "else"
  , "fallthrough"
  , "for"
  , "guard"
  , "if"
  , "in"
  , "repeat"
  , "return"
  , "switch"
  , "where"
  , "while"
  ]

reservedWordsExpressionsTypes :: [String]
reservedWordsExpressionsTypes =
  [ "as"
  , "catch"
  , "dynamicType"
  , "false"
  , "is"
  , "nil"
  , "rethrows"
  , "super"
  , "self"
  , "Self"
  , "throw"
  , "throws"
  , "true"
  , "try"
  , "__COLUMN__"
  , "__FILE__"
  , "__FUNCTION__"
  , "__LINE__"
  ]

keywordsInPatterns :: [String]
keywordsInPatterns = pure "_"

keywordsinContexts :: [String]
keywordsinContexts =
  [ "associativity"
  , "convenience"
  , "dynamic"
  , "didSet"
  , "final"
  , "get"
  , "infix"
  , "indirect"
  , "lazy"
  , "left"
  , "mutating"
  , "none"
  , "nonmutating"
  , "optional"
  , "override"
  , "postfix"
  , "precedence"
  , "prefix"
  , "Protocol"
  , "required"
  , "right"
  , "set"
  , "Type"
  , "unowned"
  , "weak"
  , "willSet"
  ]

-- Ignore Whitespace
-- C-style comments with nesting.
swiftLangDef :: L.GenLanguageDef Text st Identity
swiftLangDef = T.LanguageDef
  { T.commentStart = "/*"
  , T.commentEnd = "*/"
  , T.commentLine = "//"
  , T.nestedComments = True
  , T.identStart = P.letter
  , T.identLetter = P.alphaNum
  , T.reservedNames = reservedWordsDeclarations
                          ++ reservedWordsStatements
                          ++ reservedWordsExpressionsTypes
                          ++ keywordsInPatterns
                          ++ keywordsinContexts
  , T.opStart = P.oneOf ""
  , T.opLetter = P.oneOf ""
  , T.reservedOpNames = []
  , T.caseSensitive = True
  }

lexer :: T.GenTokenParser Text u Identity
lexer = T.makeTokenParser swiftLangDef

ws :: Parser ()
ws = T.whiteSpace lexer

comma :: Parser String
comma = T.comma lexer

colon :: Parser String
colon = T.colon lexer

semicolon :: Parser String
semicolon = T.semi lexer

optSemicolon :: Parser (Maybe String)
optSemicolon = optional semicolon

braces :: Parser a -> Parser a
braces p = do
  tok "{"
  a <- p
  tok "}"
  return a

parens :: Parser a -> Parser a
parens = T.parens lexer

brackets :: Parser a -> Parser a
brackets = T.brackets lexer

angles :: Parser a -> Parser a
angles = T.angles lexer

identifier :: Parser String
identifier = T.identifier lexer

kw :: String -> Parser ()
kw s = ws *> T.reserved lexer s

kw' :: String -> Parser String
kw' s = kw s *> pure s

op :: String -> Parser ()
op s = op' s *> pure ()

op' :: String -> Parser String
op' s = try $ do
  o <- operator
  when (s /= o) $ fail ("Expecting operator " ++ s ++ " but got " ++ o)
  return o

tok' :: String -> Parser String
tok' s = try (ws *> P.string s <* ws)

tok :: String -> Parser ()
tok s = tok' s *> pure ()

------------------------------------------------------------
-- SUMMARY OF THE GRAMMAR
------------------------------------------------------------

------------------------------------------------------------
-- Statements
------------------------------------------------------------

-- GRAMMAR OF A STATEMENT
statement :: Parser Statement
statement
   = try labeledStatement <* optSemicolon
  <|> try compilerControlStatement <* optSemicolon
  <|> loopStatement <* optSemicolon
  <|> branchStatement <* optSemicolon
  <|> controlTransferStatement <* optSemicolon
  <|> deferStatement <* optSemicolon
  <|> doStatement <* optSemicolon
  <|> DeclarationStatement <$> declaration <* optSemicolon
  <|> ExpressionStatement <$> expression <* optSemicolon

statements :: Parser [Statement]
statements = P.many statement

statements0 :: Parser [Statement]
statements0 = fromMaybe [] <$> optional statements

-- GRAMMAR OF A LOOP STATEMENT
loopStatement :: Parser Statement
loopStatement
    = kw "for" *> (forStatementTail <|> forInStatementTail)
  <|> whileStatement
  <|> repeatWhileStatement

forStatementTail :: Parser Statement
forStatementTail
    = do
        (i, e1, e2) <- forMiddle
        b <- codeBlock
        return $ ForStatement i e1 e2 b
  <|> do
        _ <- kw "for"
        (i, e1, e2) <- parens forMiddle
        b <- codeBlock
        return $ ForStatement i e1 e2 b

forMiddle :: Parser (Maybe ForInit, Maybe Expression, Maybe Expression)
forMiddle = do
          i <- optional forInit
          _ <- semicolon
          e1 <- optional expression
          _ <- semicolon
          e2 <- optional expression
          return (i, e1, e2)

forInit :: Parser ForInit
forInit
    = FiDeclaration <$> variableDeclaration
  <|> FiExpressionList <$> expressionList

forInStatementTail :: Parser Statement
forInStatementTail = do
  _ <- optional $ kw "case"
  p <- pattern
  _ <- kw "in"
  e <- expression
  w <- optional whereClause
  b <- codeBlock
  pure $ ForInStatement p e w b

-- GRAMMAR OF A WHILE STATEMENT

whileStatement :: Parser Statement
whileStatement = kw "while" *> (WhileStatement <$> conditionClause <*> codeBlock)

conditionClause :: Parser ConditionClause
conditionClause = do
  optE <- optional expression
  conditions <- conditionList
  return $ ConditionClause optE conditions
-- condition-clause → availability-condition­,­expression­

conditionList :: Parser ConditionList
conditionList = ConditionList <$> condition `P.sepBy` comma

condition :: Parser Condition
condition = availabilityCondition <|> caseCondition <|> optionalBindingCondition

caseCondition :: Parser Condition
caseCondition = do
  kw "case"
  p <- pattern
  i <- initializer
  optWC <- optional whereClause
  return $ CaseCondition p i optWC

optionalBindingCondition :: Parser Condition
optionalBindingCondition = do
  h <- optionalBindingHead
  cs <- OptionalBindingContinuations <$> optionalBindingContinuation `P.sepBy` comma
  optWC <- optional whereClause
  pure $ OptionalBindingCondition h cs optWC

optionalBindingHead :: Parser OptionalBindingContinuationHead
optionalBindingHead
    = kw "let" *> (LetOptionalBinding <$> pattern <*> initializer)
  <|> kw "var" *> (VarOptionalBinding <$> pattern <*> initializer)

optionalBindingContinuation :: Parser OptionalBindingContinuation
optionalBindingContinuation
    = OptionalBindingContinuationPattern <$> pattern <*> initializer
  <|> OptionalBindingContinuationHead <$> optionalBindingHead

-- GRAMMAR OF A REPEAT-WHILE STATEMENT
repeatWhileStatement :: Parser Statement
repeatWhileStatement = kw "repeat" *> (RepeatWhileStatement <$> codeBlock <* kw "while" <*> expression)

-- GRAMMAR OF A BRANCH STATEMENT

branchStatement :: Parser Statement
branchStatement = ifStatement <|> guardStatement <|> switchStatement

-- GRAMMAR OF AN IF STATEMENT

ifStatement :: Parser Statement
ifStatement = do
  _ <- kw "if"
  c <- conditionClause
  b <- codeBlock
  e <- optional elseClause
  return $ IfStatement c b e

elseClause :: Parser (Either CodeBlock Statement)
elseClause = do
  _ <- kw "else"
  (Left <$> codeBlock) <|> (Right <$> ifStatement)

-- GRAMMAR OF A GUARD STATEMENT

guardStatement :: Parser Statement
guardStatement = do
  _ <- kw "guard"
  c <- conditionClause
  _ <- kw "else"
  b <- codeBlock
  return $ GuardStatement c b

-- GRAMMAR OF A SWITCH STATEMENT

switchStatement :: Parser Statement
switchStatement = do
  kw "switch"
  e <- expression
  SwitchStatement e <$> braces (P.many switchCase)

switchCase :: Parser Case
switchCase
    = CaseLabel <$> caseLabel <*> statements
  <|> CaseDefault <$> (defaultLabel *> statements)

caseLabel :: Parser [PatternWhere]
caseLabel = do
  kw "case"
  cis <- caseItemList
  tok ":"
  return cis

caseItemList :: Parser [PatternWhere]
caseItemList = patternWhere `P.sepBy` comma
  where
    patternWhere = (,) <$> pattern <*> optional whereClause

defaultLabel :: Parser ()
defaultLabel = do
  kw "default"
  tok ":"
  pure ()

whereClause :: Parser WhereClause
whereClause = kw "where" *> (WhereClause <$> whereExpression)

whereExpression :: Parser Expression
whereExpression = expression

-- GRAMMAR OF A LABELED STATEMENT
labeledStatement :: Parser Statement
labeledStatement = LabelelStatement <$> statementLabel <*> (loopStatement <|> ifStatement <|> switchStatement)

statementLabel :: Parser String
statementLabel = labelName <* tok ":"

labelName :: Parser String
labelName = identifier

-- GRAMMAR OF A CONTROL TRANSFER STATEMENT

controlTransferStatement :: Parser Statement
controlTransferStatement
    = breakStatement
  <|> continueStatement
  <|> returnStatement
  <|> fallthroughStatement
  <|> throwStatement

-- GRAMMAR OF A BREAK STATEMENT
breakStatement :: Parser Statement
breakStatement = kw "break" *> (BreakStatement <$> optional labelName)

--GRAMMAR OF A CONTINUE STATEMENT
continueStatement :: Parser Statement
continueStatement = kw "continue" *> (ContinueStatement <$> optional labelName)

-- GRAMMAR OF A FALLTHROUGH STATEMENT
fallthroughStatement :: Parser Statement
fallthroughStatement = kw "fallthrough" *> pure FallthroughStatement

-- GRAMMAR OF A RETURN STATEMENT
returnStatement :: Parser Statement
returnStatement = kw "return" *> (ReturnStatement <$> optional expression)

-- GRAMMAR OF AN AVAILABILITY CONDITION

availabilityCondition :: Parser Condition
availabilityCondition = do
  _ <- tok "#available"
  AvailabilityCondition <$> braces (availabilityArgument `P.sepBy1` comma)

availabilityArgument :: Parser AvailabilityArgument
availabilityArgument
    = PlatformAvailabilityArgument <$> platformName <*> platformVersion
  <|> tok "*" *> pure PlatformWildcard

platformName :: Parser PlatformName
platformName
    = tok "iOS" *> pure IOS
  <|> tok "iOSApplicationExtension" *> pure IOSApplicationExtension
  <|> tok "OSX" *> pure OSX
  <|> tok "OSXApplicationExtension" *> pure OSXApplicationExtension
  <|> tok "watchOS" *> pure WatchOS

platformVersion :: Parser PlatformVersion
platformVersion
  = try v3 <|> try v2 <|> v1
    where
      v1 = PlatformVersion <$> decimalDigits
      pd2 = do
        d1 <- decimalDigits
        tok "."
        d2 <- decimalDigits
        return (d1, d2)
      v2 = do
        (d1, d2) <- pd2
        return $ PlatformVersion (d1 ++ "." ++ d2)
      v3 = do
        (d1, d2) <- pd2
        tok "."
        d3 <- decimalDigits
        return $ PlatformVersion (d1 ++ "." ++ d2 ++ "." ++ d3)

-- GRAMMAR OF A THROW STATEMENT
throwStatement :: Parser Statement
throwStatement = kw "throw" *> (ThrowStatement <$> expression)

-- GRAMMAR OF A DEFER STATEMENT
deferStatement :: Parser Statement
deferStatement = kw "defer" *> (DeferStatement <$> codeBlock)

-- GRAMMAR OF A DO STATEMENT
doStatement :: Parser Statement
doStatement = do
  kw "do"
  b <- codeBlock
  cs <- P.many catchClause
  return $ DoStatement b cs

catchClause :: Parser CatchClause
catchClause = do
  kw "catch"
  p <- optional pattern
  c <- optional (kw "where" *> whereClause)
  b <- codeBlock
  return $ CatchClause p c b

-- GRAMMAR OF A COMPILER CONTROL STATEMENT
compilerControlStatement :: Parser Statement
compilerControlStatement
    = try buildConfigurationStatement
  <|> lineControlStatement

-- GRAMMAR OF A BUILD CONFIGURATION STATEMENT
buildConfigurationStatement :: Parser Statement
buildConfigurationStatement = do
  tok "#if"
  c <- buildConfiguration
  ss <- statements
  eis <- P.many buildConfigurationElseifClause
  ec <- optional buildConfigurationElseClause
  tok "#endif"
  return $ BuildConfigurationStatement c ss eis ec

buildConfigurationElseifClause :: Parser BuildConfigurationElseifClause
buildConfigurationElseifClause = do
  tok "#elseif"
  c <- buildConfiguration
  ss <- statements
  return $ BuildConfigurationElseifClause c ss

buildConfigurationElseClause :: Parser BuildConfigurationElseClause
buildConfigurationElseClause = do
  tok "#else"
  ss <- statements
  return $ BuildConfigurationElseClause ss

buildConfiguration :: Parser BuildConfiguration
buildConfiguration = buildConfigurationTerm `P.chainl1` buildConfigurationOrOp
  where
    buildConfigurationOrOp = op "||" *> pure BuildConfigurationOr

buildConfigurationTerm :: Parser BuildConfiguration
buildConfigurationTerm = buildConfigurationPrimary `P.chainl1` buildConfigurationAndOp
  where
    buildConfigurationAndOp = op "&&" *> pure BuildConfigurationAnd

buildConfigurationPrimary :: Parser BuildConfiguration
buildConfigurationPrimary
    = BuildConfigurationId <$> identifier
  <|> BuildConfigurationBool <$> booleanLiteral
  <|> platformTestingFunction
  <|> op "!" *> buildConfiguration
  <|> braces buildConfiguration

platformTestingFunction :: Parser BuildConfiguration
platformTestingFunction
    = OperatingSystemTest <$> (P.string "os" *> braces operatingSystem)
  <|> ArchitectureTest <$> (P.string "arch" *> braces architecture)

operatingSystem :: Parser String
operatingSystem
    = P.string "OSX"
  <|> P.string "ioS"
  <|> P.string "watchOS"
  <|> P.string "tvOS"

architecture :: Parser String
architecture
     = P.string "i386"
   <|> P.string "x86_64"
   <|> P.string "arm"
   <|> P.string "arm64"

-- GRAMMAR OF A LINE CONTROL STATEMENT
lineControlStatement :: Parser Statement
lineControlStatement = try specifedLine <|> line
  where
    line = P.string "#line" *> pure LineControlLine
    specifedLine = do
      _ <- P.string "#line"
      n <- lineNumber
      fn <- fileName
      return $ LineControlSpecified n fn

lineNumber :: Parser Integer
lineNumber = do
  ds <- decimalDigits
  let n = read ds
  when (n <= 0) $ fail "lineNumber must be > 0"
  return n

fileName :: Parser String
fileName = staticStringLiteralInner

------------------------------------------------------------
-- Generic Parameters and Arguments
------------------------------------------------------------

-- GRAMMAR OF A GENERIC PARAMETER CLAUSE

genericParameterClause :: Parser GenericParameterClause
genericParameterClause
  = angles (GenericParameterClause <$> genericParameterList <*> optional requirementClause)

genericParameterList :: Parser [GenericParameter]
genericParameterList = genericParameter `P.sepBy1` comma

genericParameter :: Parser GenericParameter
genericParameter = try paramTypeId <|> try paramProtocol <|> paramName
  where
    paramName = GenericParamName <$> typeName
    paramTypeId = do
      t <- typeName
      tok ":"
      ti <- typeIdentifier
      pure $ GenericParamTypeId t ti
    paramProtocol = do
      t <- typeName
      tok ":"
      GenericParamProtocol t <$> protocolCompositionType

requirementClause :: Parser GenericRequirementClause
requirementClause = do
  kw "where"
  GenericRequirementClause <$> requirement `P.sepBy1` comma

requirement :: Parser TypeRequirement
requirement = conformanceRequirement <|> sameTypeRequirement

conformanceRequirement :: Parser TypeRequirement
conformanceRequirement = regular <|> protocol
  where
    regular = do
      ti1 <- typeIdentifier
      tok ":"
      ti2 <- typeIdentifier
      return $ ConformanceRequirementRegular ti1 ti2
    protocol = do
      ti <- typeIdentifier
      tok ":"
      pct <- protocolCompositionType
      return $ ConformanceRequirementProtocol ti pct

sameTypeRequirement :: Parser TypeRequirement
sameTypeRequirement = do
  ti <- typeIdentifier
  tok "="
  ty <- type_
  return $ SameTypeRequirement ti ty

-- GRAMMAR OF A GENERIC ARGUMENT CLAUSE
genericArgumentClause :: Parser [Type]
genericArgumentClause = try $ angles (P.many1 type_)

genericArgumentClause0 :: Parser [Type]
genericArgumentClause0 = fromMaybe [] <$> optional genericArgumentClause

------------------------------------------------------------
-- Declarations
------------------------------------------------------------

-- GRAMMAR OF A DECLARATION
declaration :: Parser Declaration
declaration
    = try importDeclaration
  <|> try constantDeclaration
  <|> try variableDeclaration
  <|> try typealiasDeclaration
  <|> try functionDeclaration
  <|> try enumDeclaration
  <|> try structDeclaration
  <|> try classDeclaration
  <|> try protocolDeclaration
  <|> try initializerDeclaration
  <|> try deinitializerDeclaration
  <|> try extensionDeclaration
  <|> try subscriptDeclaration
  <|> operatorDeclaration

declarations1 :: Parser [Declaration]
declarations1 = P.many1 declaration

declarations0 :: Parser [Declaration]
declarations0 = P.many declaration

-- GRAMMAR OF A TOP-LEVEL DECLARATION

topLevelDeclaration :: Parser [Statement]
topLevelDeclaration = statements0

-- GRAMMAR OF A CODE BLOCK

codeBlock :: Parser CodeBlock
codeBlock = CodeBlock <$> braces statements0

-- GRAMMAR OF AN IMPORT DECLARATION

importDeclaration :: Parser Declaration
importDeclaration
  = ImportDeclaration
      <$> attributes0
      <*  kw "import"
      <*> optional importKind
      <*> importPath

attributes :: Parser [Attribute]
attributes = P.many attribute

attributes0 :: Parser [Attribute]
attributes0 = fromMaybe [] <$> optional attributes

importKind :: Parser ImportKind
importKind = P.choice
  [ kw' "typealias"
  , kw' "struct"
  , kw' "class"
  , kw' "enum"
  , kw' "protocol"
  , kw' "var"
  , kw' "func"
  ]

importPath :: Parser ImportPath
importPath = importPathIdentifier `P.sepBy1 ` tok "."

importPathIdentifier :: Parser ImportPathIdentifier
importPathIdentifier
    = ImportIdentifier <$> identifier
  <|> ImportOperator <$> operator

-- GRAMMAR OF A CONSTANT DECLARATION

constantDeclaration :: Parser Declaration
constantDeclaration = do
  atts <- attributes0
  mods <- declarationModifiers0
  _ <- kw "let"
  is <- patternInitializerList
  return $ ConstantDeclaration atts mods is

patternInitializerList :: Parser [PatternInitializer]
patternInitializerList = patternInitializer `P.sepBy1` comma

patternInitializer :: Parser PatternInitializer
patternInitializer = PatternInitializer <$> pattern <*> optional initializer

initializer :: Parser Initializer
initializer = tok "=" *> (Initializer <$> expression)

-- GRAMMAR OF A VARIABLE DECLARATION
variableDeclaration :: Parser Declaration
variableDeclaration = DeclVariableDeclaration <$> variableDeclarationBody

variableDeclarationBody :: Parser VariableDeclaration
variableDeclarationBody
  = do
    (atts, mods) <- variableDeclarationHead
    try (varDeclPatternInit atts mods)
      <|> try (withVarNameAndType atts mods)
      <|> varDeclSimpleObserved atts mods
    where
      withVarNameAndType atts mods = do
        n <- variableName
        ta <- typeAnnotation
        try (varDeclReadOnly atts mods n ta)
          <|> try (varDeclComputed atts mods n ta)
          <|> varDeclObserved atts mods n ta

varDeclSimpleObserved :: [Attribute] -> [DeclarationModifier] -> Parser VariableDeclaration
varDeclSimpleObserved attrs mods
  = VarDeclObserved attrs mods <$> variableName <*> pure Nothing <*> (Just <$> initializer) <*> willSetDidSetBlock

varDeclPatternInit :: [Attribute] -> [DeclarationModifier] -> Parser VariableDeclaration
varDeclPatternInit atts mods = do
  r <- VarDeclPattern atts mods <$> try patternInitializerList
  P.notFollowedBy codeBlock
  return r

varDeclReadOnly :: [Attribute] -> [DeclarationModifier] -> VarName -> TypeAnnotation -> Parser VariableDeclaration
varDeclReadOnly atts mods name ta = VarDeclReadOnly atts mods name ta <$> codeBlock

varDeclComputed :: [Attribute] -> [DeclarationModifier] -> VarName -> TypeAnnotation -> Parser VariableDeclaration
varDeclComputed atts mods name ta = VarDeclGetSet atts mods name ta <$> getterSetterBlock

varDeclObserved :: [Attribute] -> [DeclarationModifier] -> VarName -> TypeAnnotation -> Parser VariableDeclaration
varDeclObserved attrs mods name ta
  = VarDeclObserved attrs mods name (Just ta) <$> optional initializer <*> willSetDidSetBlock

variableDeclarationHead :: Parser ([Attribute], [DeclarationModifier])
variableDeclarationHead = do
  attrs <- attributes0
  mods <- declarationModifiers0
  _ <- kw "var"
  return (attrs, mods)

variableName :: Parser String
variableName = identifier

getterSetterBlock :: Parser GetSetBlock
getterSetterBlock
    = GetSetBlock <$> codeBlock
  <|> braces other
  where
    other = getterFirst <|> setterFirst
    getterFirst = do
      optGC <- Just <$> getterClause
      optSC <- optional setterClause
      return $ GetSet optGC optSC
    setterFirst = do
      optSC <- Just <$> setterClause
      optGC <- optional getterClause
      return $ GetSet optGC optSC

getterClause :: Parser GetterClause
getterClause = GetterClause <$> attributes0 <*> (kw "get" *> codeBlock)

setterClause :: Parser SetterClause
setterClause = SetterClause <$> attributes0 <*> (kw "set" *> optional setterName) <*> codeBlock

setterName :: Parser Identifier
setterName = braces identifier

getterSetterKeywordBlock :: Parser GetSetBlock
getterSetterKeywordBlock = getterSetterBlock -- TODO what is this?

-- getter-setter-keyword-block → {­getter-keyword-clause­setter-keyword-clause­opt­}
-- getter-setter-keyword-block → {­setter-keyword-clause­getter-keyword-clause­}

-- getter-keyword-clause → attributes­opt­get

-- setter-keyword-clause → attributes­opt­set

willSetDidSetBlock :: Parser ObservedBlock
willSetDidSetBlock = pure ObservedBlock
-- willSet-didSet-block → {­willSet-clause­didSet-clause­opt­}
-- willSet-didSet-block → {­didSet-clause­willSet-clause­opt­}

-- willSet-clause → attributes­opt­willSet­setter-name­opt­code-block

-- didSet-clause → attributes­opt­didSet­setter-name­opt­code-block

-- GRAMMAR OF A TYPE ALIAS DECLARATION
typealiasDeclaration :: Parser Declaration
typealiasDeclaration = do
  (atts, m, name) <- typealiasHead
  t <-  typealiasAssignment
  return (TypeAlias atts m name t)

typealiasHead :: Parser ([Attribute], Maybe DeclarationModifier, String)
typealiasHead = do
  atts <- attributes0
  m <- optional accessLevelModifier
  _ <- kw "typealias"
  name <- typealiasName
  return (atts, m, name)

typealiasName :: Parser String
typealiasName = identifier

typealiasAssignment :: Parser Type
typealiasAssignment = tok "=" *> type_

-- GRAMMAR OF A FUNCTION DECLARATION
functionDeclaration :: Parser Declaration
functionDeclaration = do
   (attr, declMods) <- functionHead
   n <- functionName
   gs <- optional genericParameterClause
   (p, t, r) <- functionSignature
   b <- optional functionBody
   return $ FunctionDeclaration attr declMods n gs p t r b

functionHead :: Parser ([Attribute], [DeclarationModifier])
functionHead = do
  a <- attributes0
  m <- declarationModifiers0
  _ <- kw "func"
  return (a, m)

functionName :: Parser FunctionName
functionName
    = (FunctionNameIdent <$> identifier)
  <|> (FunctionNameOp <$> operator)

functionSignature :: Parser ([[Parameter]], Maybe String, Maybe FunctionResult)
functionSignature = do
  p <- parameterClauses
  t <- optional (kw' "throws" <|> kw' "rethrows")
  r <- optional functionResult
  return (p, t, r)

functionResult :: Parser FunctionResult
functionResult = op "->" *> (FunctionResult <$> attributes0 <*> type_)

functionBody :: Parser CodeBlock
functionBody = codeBlock

parameterClauses :: Parser [[Parameter]]
parameterClauses = P.many parameterClause

parameterClause :: Parser [Parameter]
parameterClause
    = try (parens (pure []))
  <|> parens parameterList

parameterList :: Parser [Parameter]
parameterList = parameter `P.sepBy1` comma

parameter :: Parser Parameter
parameter
    = do
        _ <- optional (kw "let")
        fn <- parameterName
        sn <- optional parameterName
        let (extern, local) = if isJust sn then (Just fn, fromJust sn) else (Nothing, fn)
        t <- typeAnnotation
        c <- optional defaultArgumentClause
        return $ ParameterLet extern local t c
  <|> do
        _ <- kw "var"
        (extern, local) <- externLocal
        t <- typeAnnotation
        c <- optional defaultArgumentClause
        return $ ParameterVar extern local t c
  <|> do
        _ <- kw "inout"
        (extern, local) <- externLocal
        t <- typeAnnotation
        return $ ParameterInOut extern local t
  <|> do -- FIXME move detection to first production
        extern <- optional externalParameterName
        local  <- localParameterName
        t <- typeAnnotation
        _ <- tok "..."
        return $ ParameterDots extern local t
  where
    externLocal = do
        extern <- optional externalParameterName
        local  <- localParameterName
        return (extern, local)

parameterName :: Parser String
parameterName = identifier <|> op' "_"

externalParameterName :: Parser String
externalParameterName = parameterName

localParameterName :: Parser String
localParameterName = parameterName

defaultArgumentClause :: Parser Expression
defaultArgumentClause = tok "=" *> expression

-- GRAMMAR OF AN ENUMERATION DECLARATION
enumDeclaration :: Parser Declaration
enumDeclaration = EnumDeclaration <$> do
  atts <- attributes0
  optMod <- optional accessLevelModifier
  unionStyleEnum atts optMod <|> rawValueStyleEnum atts optMod

unionStyleEnum :: [Attribute] -> Maybe DeclarationModifier -> Parser EnumDeclaration
unionStyleEnum atts optMod = do
  si <- optional (kw "indirect")
  let i = isJust si
  kw "enum"
  n <- enumName
  optP <- optional genericParameterClause
  ti <- optional typeInheritanceClause
  tok "{"
  ms <- P.many unionStyleEnumMember
  tok "}"
  return $ UnionEnum atts optMod i n optP ti ms

unionStyleEnumMember :: Parser UnionStyleEnumMember
unionStyleEnumMember
    = EnumMemberDeclaration <$> declaration
  <|> unionStyleEnumCaseClause

unionStyleEnumCaseClause :: Parser UnionStyleEnumMember
unionStyleEnumCaseClause = do
  atts <- attributes0
  si <- optional (kw "indirect")
  let i = isJust si
  kw "case"
  cs <- unionStyleEnumCaseList
  return $ EnumMemberCase atts i cs

unionStyleEnumCaseList :: Parser [(EnumName, Maybe Type)]
unionStyleEnumCaseList = unionStyleEnumCase `P.sepBy` comma

unionStyleEnumCase :: Parser (EnumName, Maybe Type)
unionStyleEnumCase = do
  n <- enumCaseName
  tt <- optional tupleType
  return (n, tt)

enumName :: Parser String
enumName = identifier

enumCaseName :: Parser String
enumCaseName = identifier

rawValueStyleEnum :: [Attribute] -> Maybe DeclarationModifier -> Parser EnumDeclaration
rawValueStyleEnum att optMod = do
  kw "enum"
  n <- enumName
  optGPC <- optional genericParameterClause
  tic <- typeInheritanceClause
  members <- RawValueEnumMembers <$> braces (P.many1 rawValueStyleEnumMember)
  return $ RawEnumDeclaration att optMod n optGPC tic members

rawValueStyleEnumMember :: Parser RawValueEnumMember
rawValueStyleEnumMember
    = try rawValueStyleEnumCaseClause
  <|> RawValueEnumDeclaration <$> declaration

rawValueStyleEnumCaseClause :: Parser RawValueEnumMember
rawValueStyleEnumCaseClause = do
  attrs <- attributes0
  kw "case"
  cases <- rawValueStyleEnumCaseList
  return $ RawValueEnumCaseClause attrs cases

rawValueStyleEnumCaseList :: Parser RawValueEnumCases
rawValueStyleEnumCaseList = RawValueEnumCases <$> rawValueStyleEnumCase `P.sepBy` comma

rawValueStyleEnumCase :: Parser RawValueEnumCase
rawValueStyleEnumCase = RawValueEnumCase <$> enumCaseName <*> optional rawValueAssignment

rawValueAssignment :: Parser Literal
rawValueAssignment = tok "=" *> rawValueLiteral

rawValueLiteral :: Parser Literal
rawValueLiteral
  = numericLiteral
  <|> StringLiteral <$> staticStringLiteral
  <|> booleanLiteral

structDeclaration' :: String ->
  ([Attribute] -> Maybe DeclarationModifier -> StructName -> Maybe GenericParameterClause ->
   Maybe TypeInheritanceClause -> [Declaration] -> Declaration) -> Parser Declaration
structDeclaration' keyword ctor = do
  atts <- attributes0
  optMod <- optional accessLevelModifier
  kw keyword
  n <- structName
  optGPC <- optional genericParameterClause
  optTIC <- optional typeInheritanceClause
  decls <- structBody
  return $ ctor atts optMod n optGPC optTIC decls

structBody :: Parser [Declaration]
structBody = do
  tok "{"
  ms <- P.many declaration
  tok "}"
  return ms

structName :: Parser String
structName = identifier

-- GRAMMAR OF A STRUCTURE DECLARATION

structDeclaration :: Parser Declaration
structDeclaration = structDeclaration' "struct" (StructDeclaration Struct)

-- GRAMMAR OF A CLASS DECLARATION

classDeclaration :: Parser Declaration
classDeclaration = structDeclaration' "class" (StructDeclaration Class)

-- GRAMMAR OF A PROTOCOL DECLARATION
protocolDeclaration :: Parser Declaration
protocolDeclaration = do
  atts <- attributes0
  optMod <- optional accessLevelModifier
  kw "protocol"
  n <- protocolName
  optTIC <- optional typeInheritanceClause
  b <- protocolBody
  return $ ProtocolDeclaration atts optMod n optTIC b

protocolName :: Parser String
protocolName = identifier

protocolBody :: Parser ProtocolMembers
protocolBody = ProtocolMembers <$> braces (P.many protocolMemberDeclaration)

protocolMemberDeclaration :: Parser ProtocolMember
protocolMemberDeclaration
    = protocolPropertyDeclaration
  <|> protocolMethodDeclaration
  <|> protocolInitializerDeclaration
  <|> protocolSubscriptDeclaration
  <|> protocolAssociatedTypeDeclaration

-- GRAMMAR OF A PROTOCOL PROPERTY DECLARATION
protocolPropertyDeclaration :: Parser ProtocolMember
protocolPropertyDeclaration = do
  (attrs, mods) <- variableDeclarationHead
  n <- variableName
  ta <- typeAnnotation
  gskb <- getterSetterKeywordBlock
  return $ ProtocolPropertyDeclaration attrs mods n ta gskb

-- GRAMMAR OF A PROTOCOL METHOD DECLARATION
protocolMethodDeclaration :: Parser ProtocolMember
protocolMethodDeclaration = do
  (attrs, mods) <- functionHead
  n <- functionName
  optGPC <- optional genericParameterClause
  (p, t, r) <- functionSignature
  return $ ProtocolMethodDeclaration attrs mods n optGPC p t r

-- GRAMMAR OF A PROTOCOL INITIALIZER DECLARATION
protocolInitializerDeclaration :: Parser ProtocolMember
protocolInitializerDeclaration = do
  (attrs, mods, initKind) <- initializerHead
  optGPC <- optional genericParameterClause
  pc <- parameterClause
  t <- kw' "throws" <|> kw' "rethrows" <|> pure ""
  return $ ProtocolInitializerDeclaration attrs mods initKind optGPC pc t

-- GRAMMAR OF A PROTOCOL SUBSCRIPT DECLARATION
protocolSubscriptDeclaration :: Parser ProtocolMember
protocolSubscriptDeclaration = do
  (attrs, mods, pc) <- subscriptHead
  (rAttrs, r) <- subscriptResult
  gskb <- getterSetterKeywordBlock
  return $ ProtocolSubscriptDeclaration attrs mods pc rAttrs r gskb

-- GRAMMAR OF A PROTOCOL ASSOCIATED TYPE DECLARATION
protocolAssociatedTypeDeclaration :: Parser ProtocolMember
protocolAssociatedTypeDeclaration = do
  (attrs, optMod, name) <- typealiasHead
  optTIC <- optional typeInheritanceClause
  optTy <- optional typealiasAssignment
  return $ ProtocolAssociatedTypeDeclaration attrs optMod name optTIC optTy

-- GRAMMAR OF AN INITIALIZER DECLARATION
initializerDeclaration :: Parser Declaration
initializerDeclaration = do
  (atts, mods, initKind) <- initializerHead
  optGPC <- optional genericParameterClause
  pc <- parameterClause
  t <- throwsDeclaration
  b <- initializerBody
  return $ InitializerDeclaration atts mods initKind optGPC pc t b

throwsDeclaration :: Parser String
throwsDeclaration = kw' "throws" <|> kw' "rethrows" <|> pure ""

initializerHead :: Parser ([Attribute], [DeclarationModifier], InitKind)
initializerHead = do
  atts <- attributes0
  mods <- declarationModifiers0
  i <- initKind
  return (atts, mods, i)
    where
      initKind = do
        kw "init"
        try (op "?") *> pure InitOption
          <|> try (op "!") *> pure InitForce
          <|> pure Init

initializerBody :: Parser CodeBlock
initializerBody = codeBlock

-- GRAMMAR OF A DEINITIALIZER DECLARATION
deinitializerDeclaration :: Parser Declaration
deinitializerDeclaration = do
  atts <- attributes0
  kw "deinit"
  block <- codeBlock
  return $ DeinitializerDeclaration atts block

-- GRAMMAR OF AN EXTENSION DECLARATION
extensionDeclaration :: Parser Declaration
extensionDeclaration = do
  acm <- optional accessLevelModifier
  kw "extension"
  t <- typeIdentifier
  optTIC <- optional typeInheritanceClause
  b <- extensionBody
  return $ ExtensionDeclaration acm t optTIC b

extensionBody :: Parser ExtensionBody
extensionBody = ExtensionBody <$> braces declarations0

-- GRAMMAR OF A SUBSCRIPT DECLARATION
subscriptDeclaration :: Parser Declaration
subscriptDeclaration = do
  (atts, mods, pc) <- subscriptHead
  (rAttrs, r) <- subscriptResult
  blockyThingo <- blocky
  return $ SubscriptDeclaration atts mods pc rAttrs r blockyThingo
  where
    blocky
        = SubscriptCodeBlock <$> codeBlock
      <|> SubscriptGetSetBlock <$> getterSetterBlock
      {- <|> SubscriptGetSetKeyBlock getterSetterKeywordBlock -} -- TODO getterSetterKeywordBlock

subscriptHead :: Parser ([Attribute], [DeclarationModifier], [Parameter])
subscriptHead = do
  atts <- attributes0
  mods <- declarationModifiers0
  kw "subscript"
  pc <- parameterClause
  return (atts, mods, pc)

subscriptResult :: Parser ([Attribute], Type)
subscriptResult = do
  tok "->"
  atts <- attributes0
  t <- type_
  return (atts, t)

-- GRAMMAR OF AN OPERATOR DECLARATION
operatorDeclaration :: Parser Declaration
operatorDeclaration = OperatorDeclaration <$> opTypes
  where
    opTypes
      = prefixOperatorDeclaration
      <|> postfixOperatorDeclaration
      <|> infixOperatorDeclaration

prePostfixDeclaration :: Op -> (Op -> OperatorDecl) -> Parser OperatorDecl
prePostfixDeclaration keyword ctor = do
  kw keyword
  kw "operator"
  o <- operator
  braces ws
  return $ ctor o

prefixOperatorDeclaration :: Parser OperatorDecl
prefixOperatorDeclaration = prePostfixDeclaration "prefix" PrefixOperatorDecl

postfixOperatorDeclaration :: Parser OperatorDecl
postfixOperatorDeclaration = prePostfixDeclaration "postfix" PostfixOperatorDecl

infixOperatorDeclaration :: Parser OperatorDecl
infixOperatorDeclaration = do
  kw "infix"
  kw "operator"
  o <- operator
  (optPrec, optAssoc) <- braces infixOperatorAttributes
  return $ InfixOperatorDecl o optPrec optAssoc

infixOperatorAttributes :: Parser (Maybe PrecedenceLevel, Maybe Associativity)
infixOperatorAttributes = do
  optPrec <- optional precedenceClause
  optAssoc <- optional associativityClause
  return (optPrec, optAssoc)

precedenceClause :: Parser Int
precedenceClause = kw "precedence" *> precedenceLevel

precedenceLevel :: Parser Int
precedenceLevel = do
  ds <- decimalDigits
  let n = read ds
  when (n < 0 || n > 255) $ fail "precedence level must be 0..255 inclusive"
  return n

associativityClause :: Parser Associativity
associativityClause = kw "associativity" *> associativity

associativity :: Parser Associativity
associativity
  = kw' "left" *> pure AssocLeft
  <|> kw' "right" *> pure AssocRight
  <|> kw' "none" *> pure AssocNone

-- GRAMMAR OF A DECLARATION MODIFIER
declarationModifier :: Parser DeclarationModifier
declarationModifier = modifier <|> accessLevelModifier

declarationModifiers0 :: Parser [DeclarationModifier]
declarationModifiers0 = P.many declarationModifier

modifier :: Parser DeclarationModifier
modifier = Modifier <$> P.choice
  [ kw' "class"
  , kw' "convenience"
  , kw' "dynamic"
  , kw' "final"
  , kw' "infix"
  , kw' "lazy"
  , kw' "mutating"
  , kw' "nonmutating"
  , kw' "optional"
  , kw' "override"
  , kw' "postfix"
  , kw' "prefix"
  , kw' "required"
  , kw' "static"
  , unowned
  , kw' "weak"
  ]
  where
    unowned :: Parser String
    unowned = P.choice
        [ try (unownedP "safe")
        , try (unownedP "unsafe")
        , kw' "unowned"
        ]
      where
        unownedP :: String -> Parser String
        unownedP t = do
          k <- kw' "unowned"
          l <- op' "("
          s <- kw' t
          r <- op' ")"
          pure (Prelude.concat [k, l, s, r])

accessLevelModifier :: Parser DeclarationModifier
accessLevelModifier = do
  i <- kw' "internal" <|> kw' "private" <|> kw' "public"
  p <- fromMaybe "" <$> optional setInParens
  return $ Modifier (i ++ p)
  where
    setInParens :: Parser String
    setInParens = parens (kw "set") *> pure "(set)"

------------------------------------------------------------
-- Patterns
------------------------------------------------------------

-- GRAMMAR OF A PATTERN
pattern :: Parser Pattern
pattern
    = wildcardPattern *> (WildcardPattern <$> optional typeAnnotation)
  <|> valueBindingPattern
  <|> typeCastingPattern
  <|> try optionalPattern
  <|> try (IdentifierPattern <$> identifierPattern <*> optional typeAnnotation)
  <|> TuplePattern <$> tuplePattern <*> optional typeAnnotation
  <|> ExpressionPattern <$> expression
-- pattern → tuple-pattern­type-annotation­opt­
-- pattern → enum-case-pattern­

-- GRAMMAR OF A WILDCARD PATTERN
wildcardPattern :: Parser ()
wildcardPattern = kw "_"

-- GRAMMAR OF AN IDENTIFIER PATTERN
identifierPattern :: Parser String
identifierPattern = identifier

-- GRAMMAR OF A VALUE-BINDING PATTERN
valueBindingPattern :: Parser Pattern
valueBindingPattern
    = kw "var" *> (VarPattern <$> pattern)
  <|> kw "let" *> (LetPattern <$> pattern)

-- GRAMMAR OF A TUPLE PATTERN
tuplePattern :: Parser [Pattern]
tuplePattern = parens tuplePatterns

tuplePatterns :: Parser [Pattern]
tuplePatterns = tuplePatternElement `P.sepBy` comma

tuplePatternElement :: Parser Pattern
tuplePatternElement = pattern

--GRAMMAR OF AN ENUMERATION CASE PATTERN

-- enum-case-pattern → type-identifier­opt­.­enum-case-name­tuple-pattern­opt­

-- GRAMMAR OF AN OPTIONAL PATTERN
optionalPattern :: Parser Pattern
optionalPattern = do
  ip <- identifierPattern
  tok "?"
  return $ OptionalPattern ip

-- GRAMMAR OF A TYPE CASTING PATTERN
typeCastingPattern :: Parser Pattern
typeCastingPattern = isPattern <|> asPattern

isPattern :: Parser Pattern
isPattern = kw "is" *> (IsPattern <$> type_)

asPattern :: Parser Pattern
asPattern = kw "as" *> (IsPattern <$> type_)

-- GRAMMAR OF AN EXPRESSION PATTERN
-- Implemented above.

------------------------------------------------------------
-- Attributes
------------------------------------------------------------

-- GRAMMAR OF AN ATTRIBUTE
attribute :: Parser Attribute
attribute = do
  tok "@"
  n <- attributeName
  optAAC <- optional attributeArgumentClause
  return $ Attribute n optAAC

attributeName :: Parser AttributeName
attributeName = identifier

attributeArgumentClause :: Parser String
attributeArgumentClause = parens balancedTokens

balancedTokens :: Parser String
balancedTokens = Prelude.concat <$> P.many balancedToken

balancedToken :: Parser String
balancedToken = parensToken <|> bracketsToken <|> bracesToken <|> anyBut
  where
    parensToken = do
      s <- parens balancedTokens
      return $ "(" ++ s ++ ")"
    bracketsToken = do
      s <- brackets balancedTokens
      return $ "[" ++ s ++ "]"
    bracesToken = do
      s <- braces balancedTokens
      return $ "{" ++ s ++ "}"
    anyBut = P.many1 (P.noneOf "()[]{}")

------------------------------------------------------------
-- Expressions
------------------------------------------------------------

-- GRAMMAR OF AN EXPRESSION

expression :: Parser Expression
-- expression = Expression
--   <$> optional tryOperator
--   <*> prefixExpression
--   <*> (fromMaybe [] <$> optional binaryExpressions)

expression = do
  t <- optional tryOperator
  p <- prefixExpression
  bs <- optional binaryExpressions
  return $ Expression t p (fromMaybe [] bs)

expressionList :: Parser [Expression]
expressionList = expression `P.sepBy1` comma

-- GRAMMAR OF A PREFIX EXPRESSION

prefixExpression :: Parser PrefixExpression
prefixExpression = try inOutExpression <|> prefixExpression1

prefixExpression1 :: Parser PrefixExpression
prefixExpression1 = do
  o <- optional prefixOperator
  pe <- postfixExpression
  return $ PrefixExpression o pe

inOutExpression :: Parser PrefixExpression
inOutExpression = InOutExpression <$> (op "&" *> identifier)

-- GRAMMAR OF A TRY EXPRESSION

tryOperator :: Parser String
tryOperator
    = kw' "try"
  <|> kw' "try?"
  <|> kw' "try!"

-- GRAMMAR OF A BINARY EXPRESSION

binaryExpression :: Parser BinaryExpression
binaryExpression
    = do
        co <- conditionalOperator
        to <- optional tryOperator
        pe <- prefixExpression
        return $ BinaryConditional co to pe
 <|> do
        _ <- assignmentOperator
        to <- optional tryOperator
        pe <- prefixExpression
        return $ BinaryAssignmentExpression to pe
  <|> typeCastingOperator
  <|> do
        o <- binaryOperator
        e <- prefixExpression
        return $ BinaryExpression1 o e

binaryExpressions :: Parser [BinaryExpression]
binaryExpressions = P.many binaryExpression

-- GRAMMAR OF AN ASSIGNMENT OPERATOR
assignmentOperator :: Parser ()
assignmentOperator = try $ do
  ws
  _ <- P.char '='
  try (P.notFollowedBy operatorCharacter)
  ws
  return ()

-- GRAMMAR OF A CONDITIONAL OPERATOR
conditionalOperator :: Parser (Maybe String, Expression)
conditionalOperator = do
  _ <- op "?"
  to <- optional tryOperator
  e <- expression
  _ <- tok ":"
  return (to, e)

-- GRAMMAR OF A TYPE-CASTING OPERATOR
typeCastingOperator :: Parser BinaryExpression
typeCastingOperator
    = try (BinaryExpression4 <$> kw' "is" <*> type_)
  <|> try (BinaryExpression4 <$> kw' "as" <*> type_)
  <|> try (do
        k <- kw' "as"
        o <- op' "?"
        t <- type_
        return $ BinaryExpression4 (k ++ o) t)
  <|> try (do
        k <- kw' "as"
        o <- op' "!"
        t <- type_
        return $ BinaryExpression4 (k ++ o) t
      )

-- GRAMMAR OF A PRIMARY EXPRESSION
primaryExpression :: Parser PrimaryExpression
primaryExpression
    = PrimaryExpression1 <$> (IdG <$> identifier <*> (fromMaybe [] <$> optional genericArgumentClause))
  <|> PrimaryLiteral <$> literalExpression
  <|> PrimarySelf <$> selfExpression
  <|> PrimarySuper <$> superclassExpression
  <|> PrimaryClosure <$> closureExpression
  <|> PrimaryParenthesized <$> parenthesizedExpression
  <|> implicitMemberExpression
  <|> pure PrimaryWildcard <* wildCardExpression

-- GRAMMAR OF A LITERAL EXPRESSION
literalExpression :: Parser LiteralExpression
literalExpression
    = RegularLiteral <$> literal
  <|> try arrayLiteral
  <|> dictionaryLiteral
  <|> SpecialLiteral <$> P.choice
        [ kw' "__FILE__"
        , kw' "__LINE__"
        , kw' "__COLUMN__"
        , kw' "__FUNCTION__"
        ]

arrayLiteral :: Parser LiteralExpression
arrayLiteral = ArrayLiteral <$> arrayLiteralItems

arrayLiteralItems :: Parser [Expression]
arrayLiteralItems = brackets (arrayLiteralItem `P.sepBy` comma)

arrayLiteralItem :: Parser Expression
arrayLiteralItem = expression

dictionaryLiteral :: Parser LiteralExpression
dictionaryLiteral = DictionaryLiteral <$> (items <|> noItems)
  where
    items = brackets dictionaryLiteralItems
    noItems = brackets (op ":") *> pure []

dictionaryLiteralItems :: Parser [(Expression, Expression)]
dictionaryLiteralItems = dictionaryLiteralItem `P.sepBy1` comma

dictionaryLiteralItem :: Parser (Expression, Expression)
dictionaryLiteralItem = (,) <$> (expression <* tok ":") <*> expression

-- GRAMMAR OF A SELF EXPRESSION
selfExpression :: Parser SelfExpression
selfExpression = kw "self" *> P.choice
  [ try (pure SelfMethod <* tok "." <*> identifier)
  , try (pure SelfSubscript <*> brackets expressionList)
  , try (pure SelfInit <* tok "." <* kw "init")
  , try (pure Self)
  ]

-- GRAMMAR OF A SUPERCLASS EXPRESSION
superclassExpression :: Parser SuperclassExpression
superclassExpression = kw "super" *> P.choice
  [ try (pure SuperMethod <* tok "." <*> identifier)
  , try (pure SuperSubscript <*> brackets expressionList)
  , try (pure SuperInit <* tok "." <* kw "init")
  ]

-- GRAMMAR OF A CLOSURE EXPRESSION

closureExpression :: Parser Closure
closureExpression = braces (Closure <$> optional closureSignature <*> statements)

closureSignature :: Parser ClosureSig
closureSignature = do
  sig <- paramSig <|> identsSig <|> captureSig
  kw "in"
  return sig
  where
    paramSig = do
      pc <- parameterClause
      optR <- optional functionResult
      return $ ClosureSigParam Nothing pc optR
    identsSig = do
      idents <- identifierList
      optR <- optional functionResult
      return $ ClosureSigIdents Nothing idents optR
    captureSig = do
      captures <- captureList
      captureParam captures <|> captureIdents captures <|> noIdents captures
        where
          captureParam captures = do
            pc <- parameterClause
            optR <- optional functionResult
            return $ ClosureSigParam (Just captures) pc optR
          captureIdents captures = do
            idents <- identifierList
            optR <- optional functionResult
            return $ ClosureSigIdents (Just captures) idents optR
          noIdents captures = return $ ClosureSigIdents (Just captures) [] Nothing

captureList :: Parser CaptureList
captureList = CaptureList <$> brackets captureListItems

captureListItems :: Parser [Capture]
captureListItems = captureListItem `P.sepBy1` comma

captureListItem :: Parser Capture
captureListItem = do
  optSpec <- optional captureSpecifier
  e <- expression
  return $ Capture optSpec e

captureSpecifier :: Parser CaptureSpecifier
captureSpecifier = weak <|> try unownedSafe <|> try unownedUnsafe <|> unowned
  where
    weak = kw "weak" *> pure Weak
    unowned = kw "unowned" *> pure Unowned
    unownedSafe = do
      kw "weak"
      parens (kw "safe")
      return UnownedSafe
    unownedUnsafe = do
      kw "weak"
      parens (kw "unsafe")
      return UnownedUnsafe

-- GRAMMAR OF A IMPLICIT MEMBER EXPRESSION
implicitMemberExpression :: Parser PrimaryExpression
implicitMemberExpression = do
  tok "."
  ident <- identifier
  return $ PrimaryImplicitMember ident

-- GRAMMAR OF A PARENTHESIZED EXPRESSION

parenthesizedExpression :: Parser [ExpressionElement]
parenthesizedExpression = P.choice
  [ try (parens (pure []))
  , parens expressionElementList
  ]

expressionElementList :: Parser [ExpressionElement]
expressionElementList = expressionElement `P.sepBy` comma

expressionElement :: Parser ExpressionElement
expressionElement
    = try (ExpressionElement <$> (Just <$> identifier) <* colon <*> expression)
  <|> ExpressionElement <$> pure Nothing <*> expression

-- GRAMMAR OF A WILDCARD EXPRESSION
wildCardExpression :: Parser ()
wildCardExpression = tok "_"

-- GRAMMAR OF A POSTFIX EXPRESSION

postfixExpression :: Parser PostfixExpression
postfixExpression = postfixExpressionOuter

notFollowedByPrimary :: Parser ()
notFollowedByPrimary = P.notFollowedBy primaryExpression

postfixExpressionOuter :: Parser PostfixExpression
postfixExpressionOuter = do
  e1 <- postfixExpressionInner
  e2 <- forcedValueExpressionTail e1 <* notFollowedByPrimary
    <|> optionalChainingExpressionTail e1 <* notFollowedByPrimary
    <|> postfixOpTail e1
    <|> dotTail e1
    <|> (FunctionCallE <$> functionCallTail e1)
    <|> Subscript <$> pure e1 <*> brackets expressionList
    <|> pure e1
  pure e2
    where
      postfixOpTail :: PostfixExpression -> Parser PostfixExpression
      postfixOpTail e = try $ do
        o <- operator
        notFollowedByPrimary
        return $ PostfixOperator e o
      dotTail :: PostfixExpression -> Parser PostfixExpression
      dotTail e = do
        _ <- tok "."
        postfixDynamicTypeTail e
          <|> postfixInitTail e
          <|> postfixSelfTail e
          <|> explicitMemberExpressionTail e

postfixExpressionInner :: Parser PostfixExpression
postfixExpressionInner = PostfixPrimary <$> primaryExpression

-- GRAMMAR OF A FUNCTION CALL EXPRESSION

functionCallTail :: PostfixExpression -> Parser FunctionCall
functionCallTail postfixE = do
  pe <- parenthesizedExpression
  c <- optional trailingClosure
  pure $ FunctionCall postfixE pe c

functionCallExpression :: Parser FunctionCall
functionCallExpression = do
  postfixE <- postfixExpression
  functionCallTail postfixE

trailingClosure :: Parser Closure
trailingClosure = closureExpression

-- GRAMMAR OF AN INITIALIZER EXPRESSION
-- We have already parsed postfixExpression and ".".
postfixInitTail :: PostfixExpression -> Parser PostfixExpression
postfixInitTail postfixE = kw "init" *> pure (PostfixExpression4Initalizer postfixE)

-- GRAMMAR OF AN EXPLICIT MEMBER EXPRESSION
-- We have already parsed postExpression and ".".
explicitMemberExpressionTail :: PostfixExpression -> Parser PostfixExpression
explicitMemberExpressionTail postfixE
    = try (ExplicitMemberExpressionDigits <$> pure postfixE <*> decimalDigits)
  <|> ExplicitMemberExpressionIdentifier <$> pure postfixE <*>
        (IdG <$> identifier <*> (fromMaybe [] <$> optional genericArgumentClause))

-- GRAMMAR OF A SELF EXPRESSION
-- We have already parsed postfixExpression and ".".
postfixSelfTail :: PostfixExpression -> Parser PostfixExpression
postfixSelfTail postfixE = kw "self" *> pure (PostfixSelf postfixE)

-- GRAMMAR OF A DYNAMIC TYPE EXPRESSION
postfixDynamicTypeTail :: PostfixExpression -> Parser PostfixExpression
postfixDynamicTypeTail postfixE = kw "dynamicType" *> pure (PostfixDynamicType postfixE)

-- GRAMMAR OF A SUBSCRIPT EXPRESSION
-- See Subscript above.

-- GRAMMAR OF A FORCED-VALUE EXPRESSION
forcedValueExpressionTail :: PostfixExpression -> Parser PostfixExpression
forcedValueExpressionTail e = op "!" *> pure (PostfixForcedValue e)

-- GRAMMAR OF AN OPTIONAL-CHAINING EXPRESSION
optionalChainingExpressionTail :: PostfixExpression -> Parser PostfixExpression
optionalChainingExpressionTail e = try $ do
  _ <- op "?"
  notFollowedByPrimary
  return $ PostfixOptionChaining e

------------------------------------------------------------
-- Lexical Structure
------------------------------------------------------------

-- GRAMMAR OF AN IDENTIFIER

-- identifier → identifier-head­identifier-characters­opt­
-- identifier → `­identifier-head­identifier-characters­opt­`­
-- identifier → implicit-parameter-name­

identifierList :: Parser [Identifier]
identifierList = P.many1 identifier

-- identifier-list → identifier­  identifier­,­identifier-list­
-- identifier-head → Upper- or lowercase letter A through Z
-- identifier-head → _­
-- identifier-head → U+00A8, U+00AA, U+00AD, U+00AF, U+00B2–U+00B5, or U+00B7–U+00BA
-- identifier-head → U+00BC–U+00BE, U+00C0–U+00D6, U+00D8–U+00F6, or U+00F8–U+00FF
-- identifier-head → U+0100–U+02FF, U+0370–U+167F, U+1681–U+180D, or U+180F–U+1DBF
-- identifier-head → U+1E00–U+1FFF
-- identifier-head → U+200B–U+200D, U+202A–U+202E, U+203F–U+2040, U+2054, or U+2060–U+206F
-- identifier-head → U+2070–U+20CF, U+2100–U+218F, U+2460–U+24FF, or U+2776–U+2793
-- identifier-head → U+2C00–U+2DFF or U+2E80–U+2FFF
-- identifier-head → U+3004–U+3007, U+3021–U+302F, U+3031–U+303F, or U+3040–U+D7FF
-- identifier-head → U+F900–U+FD3D, U+FD40–U+FDCF, U+FDF0–U+FE1F, or U+FE30–U+FE44
-- identifier-head → U+FE47–U+FFFD
-- identifier-head → U+10000–U+1FFFD, U+20000–U+2FFFD, U+30000–U+3FFFD, or U+40000–U+4FFFD
-- identifier-head → U+50000–U+5FFFD, U+60000–U+6FFFD, U+70000–U+7FFFD, or U+80000–U+8FFFD
-- identifier-head → U+90000–U+9FFFD, U+A0000–U+AFFFD, U+B0000–U+BFFFD, or U+C0000–U+CFFFD
-- identifier-head → U+D0000–U+DFFFD or U+E0000–U+EFFFD
-- identifier-character → Digit 0 through 9
-- identifier-character → U+0300–U+036F, U+1DC0–U+1DFF, U+20D0–U+20FF, or U+FE20–U+FE2F
-- identifier-character → identifier-head­
-- identifier-characters → identifier-character­identifier-characters­opt­
-- implicit-parameter-name → $­decimal-digits­

-- GRAMMAR OF A LITERAL
literal :: Parser Literal
literal = ws *>
  (try numericLiteral <|> try stringLiteral <|> try booleanLiteral <|> nilLiteral) <* ws

numericLiteral :: Parser Literal
numericLiteral = try optNegFloatingPointLiteral <|> optNegIntegerLiteral
  where
    optNegIntegerLiteral = do
      n <- optional (P.string "-")
      i <- integerLiteral
      return $ apply (neg n) i
    optNegFloatingPointLiteral = do
      n <- optional (P.string "-")
      f <- floatingPointLiteral
      return $ apply (neg n) f
    neg = maybe "" (const "-")
    apply n (NumericLiteral s) = NumericLiteral $ n ++ s
    apply _ _ = error "why know we have a NumericLiteral here"

booleanLiteral :: Parser Literal
booleanLiteral = BooleanLiteral <$>
     (kw "true" *> pure True
  <|> kw "false" *> pure False)

nilLiteral :: Parser Literal
nilLiteral = pure NilLiteral <* kw "nil"

-- GRAMMAR OF AN INTEGER LITERAL
-- TODO use P.lookAhead here with case..of.
integerLiteral :: Parser Literal
integerLiteral
    = NumericLiteral <$>
         (try binaryLiteral
      <|> try octalLiteral
      <|> try hexLiteral
      <|> decimalLiteral)

binaryLiteral :: Parser String
binaryLiteral = do
  b <- P.string "0b"
  digits <- P.many1 binaryLiteralCharacter
  return $ b ++ digits
  where
    binaryDigit = P.oneOf ['0'..'1']
    binaryLiteralCharacter = binaryDigit <|> P.char '_'

octalLiteral :: Parser String
octalLiteral = do
  o <- P.string "0o"
  digits <- P.many1 octalLiteralCharacter
  return $ o ++ digits
  where
    octalDigit = P.oneOf ['0'..'7']
    octalLiteralCharacter = octalDigit <|> P.char '_'

decimalLiteral :: Parser String
decimalLiteral = P.many1 decimalLiteralCharacter
  where
    decimalLiteralCharacter = decimalDigit <|> P.char '_'

decimalDigit :: Parser Char
decimalDigit = P.oneOf ['0'..'9']

decimalDigits :: Parser String
decimalDigits = P.many1 decimalDigit

hexadecimalLiteral :: Parser String
hexadecimalLiteral = P.many1 hexLiteralCharacter
  where
    hexLiteralCharacter = hexDigit <|> P.char '_'

hexLiteral :: Parser String
hexLiteral = do
  h <- P.string "0x"
  digits <- P.many1 hexLiteralCharacter
  return $ h ++ digits
  where
    hexLiteralCharacter = hexDigit <|> P.char '_'

hexDigit :: Parser Char
hexDigit = P.oneOf (['0'..'9'] ++ ['a'..'f'] ++ ['A'..'F'])

stringyOptional :: Parser String -> Parser String
stringyOptional p = try p <|> pure ""

-- GRAMMAR OF A FLOATING-POINT LITERAL
floatingPointLiteral :: Parser Literal
floatingPointLiteral = try hexFloatingPoint <|> decFloatingPoint

decFloatingPoint :: Parser Literal
decFloatingPoint = do
  d <- decimalLiteral
  f <- stringyOptional decimalFraction
  e <- stringyOptional decimalExponent
  when (f == "" && e == "") $ fail "we want to parse an dec here"
  return $ NumericLiteral (d ++ f ++ e)

hexFloatingPoint :: Parser Literal
hexFloatingPoint = do
  h <- hexLiteral
  f <- stringyOptional hexFraction
  e <- stringyOptional hexExponent
  if f == "" && e == "" then fail "we want to parse a regular hex here" else pure ()
  return $ NumericLiteral (h ++ f ++ e)

decimalFraction :: Parser String
decimalFraction = do
  dot <- tok' "."
  dec <- decimalLiteral
  return $ dot ++ dec

decimalExponent :: Parser String
decimalExponent = do
  e <- floatingPointE
  s <- stringyOptional sign
  dec <- decimalLiteral
  return $ e ++ s ++ dec

hexFraction :: Parser String
hexFraction = do
  dot <- tok' "."
  hex <- hexadecimalLiteral
  return $ dot ++ hex

hexExponent :: Parser String
hexExponent = do
  e <- floatingPointP
  s <- stringyOptional sign
  hex <- decimalLiteral
  return $ e ++ s ++ hex

floatingPointE :: Parser String
floatingPointE = (: []) <$> P.oneOf "eE"

floatingPointP :: Parser String
floatingPointP = (: []) <$> P.oneOf "pP"

sign :: Parser String
sign = (: []) <$> P.oneOf "+-"

-- GRAMMAR OF A STRING LITERAL
stringLiteral :: Parser Literal
stringLiteral = StringLiteral <$> (try staticStringLiteral <|> interpolatedStringLiteral)

staticStringLiteral :: Parser StringLiteral
staticStringLiteral = StaticStringLiteral <$> staticStringLiteralInner

staticStringLiteralInner :: Parser String
staticStringLiteralInner = do
  _ <- P.char '"'
  is <- P.many quotedTextItem
  _ <- P.char '"'
  return $ Prelude.concat is

quotedTextItem :: Parser String
quotedTextItem
    = escapedCharacter
  <|> P.many1 (P.noneOf "\"\\\x000A\x000D") -- any Unicode scalar value except " (double-quote), \ (backslash), U+000A, or U+000D

interpolatedStringLiteral :: Parser StringLiteral
interpolatedStringLiteral = InterpolatedStringLiteral <$> do
  _ <- P.char '"'
  tis <- P.many interpolatedTextItem
  _ <- P.char '"'
  return tis

interpolatedTextItem :: Parser InterpolatedTextItem
interpolatedTextItem
    = try $ TextItemExpr <$> do
        _ <- P.string "\\("
        e <- expression
        _ <- P.string ")"
        return e
    <|> TextItemString <$> quotedTextItem

escapedCharacter :: Parser String
escapedCharacter
    = (try . P.string) "\\0" *> pure "\0"
  <|> (try . P.string) "\\\\" *> pure "\\"
  <|> (try . P.string) "\\t" *> pure "\t"
  <|> (try . P.string) "\\n" *> pure "\n"
  <|> (try . P.string) "\\r" *> pure "\r"
  <|> (try . P.string) "\\\"" *> pure "\""
  <|> (try . P.string) "\\'" *> pure "'"
  <|> do
        u <- P.string "\\u"
        d <- unicodeScalarDigits
        return $ u ++ d

-- 1..8 hex digits
unicodeScalarDigits :: Parser String
unicodeScalarDigits = P.choice
  [ P.count 8 hexDigit
  , P.count 7 hexDigit
  , P.count 6 hexDigit
  , P.count 5 hexDigit
  , P.count 4 hexDigit
  , P.count 3 hexDigit
  , P.count 2 hexDigit
  , P.count 1 hexDigit
  ]

-- GRAMMAR OF OPERATORS

operator :: Parser String
operator
    = try $ do
        _ <- ws
        h <- operatorHead
        cs <- operatorCharacters
        _ <- ws
        return (h : cs)
  <|> do
        _ <- ws
        _ <- P.char '`'
        h <- operatorHead
        cs <- operatorCharacters
        _ <- P.char '`'
        _ <- ws
        return (h : cs)

legalHeadOperatorChars :: String
legalHeadOperatorChars =
  "=/-+!*%<>&|^~?"
  ++ ['\x00A1' .. '\x00A7']
  ++ "\x00A9\x00AB"
  ++ "\x00AC\x00AE"
  ++ ['\x00B0'..'\x00B1'] ++ "\x00B6\x00BB\x00BF\x00D7\x00F7"
  ++ ['\x2016'..'\x2017'] ++ ['\x2020'..'\x2027']
  ++ ['\x2030'..'\x203E']
  ++ ['\x2041'..'\x2053']
  ++ ['\x2055'..'\x205E']
  ++ ['\x2190'..'\x23FF']
  ++ ['\x2500'..'\x2775']
  ++ ['\x2794'..'\x2BFF']
  ++ ['\x2E00'..'\x2E7F']
  ++ ['\x3001'..'\x3003']
  ++ ['\x3008'..'\x3030']

legalTailOperatorChars :: String
legalTailOperatorChars = legalHeadOperatorChars
  ++ ['\x0300'..'\x036F']
  ++ ['\x1DC0'..'\x1DFF']
  ++ ['\x20D0'..'\x20FF']
  ++ ['\xFE00'..'\xFE0F']
  ++ ['\xFE20'..'\xFE2F']
  ++ ['\xE0100'..'\xE01FF']

operatorHead :: Parser Char
operatorHead = P.oneOf legalHeadOperatorChars

operatorCharacter :: Parser Char
operatorCharacter = P.oneOf legalTailOperatorChars

operatorCharacters :: Parser String
operatorCharacters = P.many operatorCharacter

-- dotOperatorHead = P.string ".."
-- dotOperatorCharacter = P.string "." <|> operatorCharacter
-- dotOperatorCharacters = P.many dotOperatorCharacter

binaryOperator :: Parser String
binaryOperator = operator

prefixOperator :: Parser String
prefixOperator = operator

postfixOperator :: Parser String
postfixOperator = operator

------------------------------------------------------------
-- Types
------------------------------------------------------------
type_ :: Parser Type
type_ = do
  t <- type_1
  (metaTypeTail t <|> optionalTypeTail t <|> implicitlyUnwrappedOptionalTypeTail t) <|> pure t

type_1 :: Parser Type
type_1 = primType_ `P.chainr1` functionTypeOp

-- GRAMMAR OF A TYPE
primType_ :: Parser Type
primType_
    = try arrayType
  <|> dictionaryType
  <|> protocolCompositionType
  <|> tupleType
  <|> typeIdentifierType

typeIdentifierType :: Parser Type
typeIdentifierType = TypeIdentifierType <$> typeIdentifier

-- GRAMMAR OF A TYPE ANNOTATION
typeAnnotation :: Parser TypeAnnotation
typeAnnotation = tok ":" *> (TypeAnnotation <$> attributes0 <*> type_)

mySepBy1 :: Parser a -> Parser sep -> Parser [a]
mySepBy1 p sep = do
  x <- p
  xs <- many trying
  return (x:xs)
    where
      trying = try (sep >> p)

-- GRAMMAR OF A TYPE IDENTIFIER
typeIdentifier :: Parser TypeIdentifier
typeIdentifier = TypeIdentifier <$> (nameOptGAC `mySepBy1` tok ".")
  where
    nameOptGAC = (,) <$> typeName <*> genericArgumentClause0

typeName :: Parser TypeName
typeName = identifier

-- GRAMMAR OF A TUPLE TYPE
tupleType :: Parser Type
tupleType = TupleType <$> braces (optional tupleTypeBody)

tupleTypeBody :: Parser TupleTypeBody
tupleTypeBody = do
  elements <- tupleTypeElement `P.sepBy` comma
  dots <- tok "..." *> pure True <|> pure False
  return $ TupleTypeBody elements dots

tupleTypeElement :: Parser TupleElementType
tupleTypeElement = try anon <|> named
  where
    anon = do
      attrs <- attributes0
      optInout <- optionalInOut
      t <- type_
      return $ TupleElementTypeAnon attrs optInout t
    named = do
      optInOut <- optionalInOut
      n <- elementName
      ta <- typeAnnotation
      return $ TupleElementTypeNamed optInOut n ta
    optionalInOut = optional (kw "inout" *> pure InOut)

elementName :: Parser ElementName
elementName = identifier

-- GRAMMAR OF A FUNCTION TYPE
functionTypeOp :: Parser (Type -> Type -> Type)
functionTypeOp = do
  throws <- kw' "throws" <|> kw' "rethrows" <|> pure ""
  tok "->"
  return $ FunctionType throws

-- GRAMMAR OF AN ARRAY TYPE
arrayType :: Parser Type
arrayType = ArrayType <$> brackets type_

-- GRAMMAR OF A DICTIONARY TYPE
dictionaryType :: Parser Type
dictionaryType = brackets inner
  where
    inner = do
      t1 <- type_
      tok ":"
      t2 <- type_
      return $ DictionaryType t1 t2

-- GRAMMAR OF AN OPTIONAL TYPE
optionalTypeTail :: Type -> Parser Type
optionalTypeTail t = op "?" *> pure (TypeOpt t)

-- GRAMMAR OF AN IMPLICITLY UNWRAPPED OPTIONAL TYPE
implicitlyUnwrappedOptionalTypeTail :: Type -> Parser Type
implicitlyUnwrappedOptionalTypeTail t = op "!" *> pure (ImplicitlyUnwrappedOptType t)

-- GRAMMAR OF A PROTOCOL COMPOSITION TYPE
protocolCompositionType :: Parser Type
protocolCompositionType = do
  kw "protocol"
  ids <- angles (protocolIdentifier `P.sepBy` comma)
  return $ ProtocolCompositionType ids

protocolIdentifier :: Parser ProtocolIdentifier
protocolIdentifier = typeIdentifier

-- GRAMMAR OF A METATYPE TYPE
metaTypeTail :: Type -> Parser Type
metaTypeTail t = typeMetaType <|> protocolMetaType
  where
    typeMetaType = do
      tok "."
      kw "Type"
      return $ TypeMetaType t
    protocolMetaType = do
      tok "."
      kw "Protocol"
      return $ ProtocolMetaType t

-- GRAMMAR OF A TYPE INHERITANCE CLAUSE
typeInheritanceClause :: Parser TypeInheritanceClause
typeInheritanceClause = do
  tok ":"
  try classy <|> listy
  where
    classy = kw "class" *> (TypeInheritanceClause True <$> listy')
    listy = TypeInheritanceClause False <$> listy'
    listy' = typeIdentifier `P.sepBy` comma
