module Language.Swift.Quote.Syntax where

data Module = Module [Statement]
  deriving (Show, Eq)

data Expression
  = Expression (Maybe String) PrefixExpression [BinaryExpression]
  deriving (Show, Eq)

data PrefixExpression
  = PrefixExpression (Maybe String) {- prefixOperator -} PostfixExpression
  | InOutExpression String -- identifier
  deriving (Show, Eq)

data IdG = IdG
  { idgIdentifier :: String
  , idgGenericArgs :: [Type]
  }
  deriving (Show, Eq)

data PostfixExpression
  = PostfixPrimary PrimaryExpression
  | PostfixOperator PostfixExpression String -- postfix-operator
  | ExplicitMemberExpressionDigits PostfixExpression String -- digits
  | ExplicitMemberExpressionIdentifier PostfixExpression IdG
  | FunctionCallE FunctionCall
  | PostfixExpression4Initalizer PostfixExpression
  | PostfixSelf PostfixExpression
  | PostfixDynamicType PostfixExpression
  | PostfixForcedValue PostfixExpression
  | PostfixOptionChaining PostfixExpression
  | Subscript PostfixExpression [Expression]
  deriving (Show, Eq)

data ExpressionElement = ExpressionElement (Maybe String) Expression
  deriving (Show, Eq)

data FunctionCall = FunctionCall PostfixExpression [ExpressionElement] (Maybe Closure)
  deriving (Show, Eq)

type ParamClause = [Parameter]

data CaptureSpecifier = Weak | Unowned | UnownedSafe | UnownedUnsafe
  deriving (Show, Eq)

data Capture = Capture (Maybe CaptureSpecifier) Expression
  deriving (Show, Eq)

data CaptureList = CaptureList [Capture]
  deriving (Show, Eq)

data ClosureSig
  = ClosureSigParam  (Maybe CaptureList) ParamClause  {- optResult -}(Maybe FunctionResult)
  | ClosureSigIdents (Maybe CaptureList) [Identifier] {- optResult -}(Maybe FunctionResult)
  deriving (Show, Eq)

data Closure = Closure (Maybe ClosureSig) [Statement]
  deriving (Show, Eq)

data PrimaryExpression
  = PrimaryExpression1 IdG
  | PrimaryLiteral LiteralExpression
  | PrimarySelf SelfExpression
  | PrimarySuper SuperclassExpression
  | PrimaryClosure Closure
  | PrimaryParenthesized [ExpressionElement] -- parenthesized-expression
  | PrimaryImplicitMember Identifier
  | PrimaryWildcard -- wildcard-expression
  deriving (Show, Eq)

data SelfExpression
  = Self
  | SelfMethod Identifier
  | SelfSubscript [Expression]
  | SelfInit
  deriving (Show, Eq)

data SuperclassExpression
  = SuperMethod Identifier
  | SuperSubscript [Expression]
  | SuperInit
  deriving (Show, Eq)

data Literal
  = NumericLiteral String
  | StringLiteral StringLiteral
  | BooleanLiteral Bool
  | NilLiteral
  deriving (Show, Eq)

data StringLiteral
  = StaticStringLiteral String
  | InterpolatedStringLiteral [InterpolatedTextItem]
  deriving (Show, Eq)

data InterpolatedTextItem
  = TextItemString String
  | TextItemExpr Expression
  deriving (Show, Eq)

data LiteralExpression
  = RegularLiteral Literal
  | ArrayLiteral [Expression]
  | DictionaryLiteral [(Expression, Expression)]
  | SpecialLiteral String
  deriving (Show, Eq)

data BinaryExpression
  = BinaryExpression1
    { beOperator :: String
    , bePrefixExpression :: PrefixExpression
    }
  | BinaryAssignmentExpression
    { beTryOperator :: Maybe String
    , bePrefixExpression :: PrefixExpression
    }
  | BinaryConditional (Maybe TryOp, Expression) (Maybe TryOp) PrefixExpression
  | BinaryExpression4 String Type
  deriving (Show, Eq)

type TryOp = String

data Statement
  = ExpressionStatement Expression
  | ForStatement
    { forInitE :: Maybe ForInit
    , forCondE :: Maybe Expression
    , forNextE :: Maybe Expression
    , forBlock :: CodeBlock
    }
  | ForInStatement
    { fiPattern :: Pattern
    , fiExpression :: Expression
    , fiWhereClause :: Maybe WhereClause
    , fiBlock :: CodeBlock
    }
  | DeclarationStatement Declaration
  | ReturnStatement (Maybe Expression)
  | WhileStatement ConditionClause CodeBlock
  | RepeatWhileStatement CodeBlock Expression
  | GuardStatement ConditionClause CodeBlock
  | SwitchStatement Expression [Case]
  | IfStatement ConditionClause CodeBlock (Maybe (Either CodeBlock {- if -}Statement))
  | LabelelStatement LabelName Statement
  | BreakStatement (Maybe LabelName)
  | ContinueStatement (Maybe LabelName)
  | FallthroughStatement
  | ThrowStatement Expression
  | DeferStatement CodeBlock
  | DoStatement CodeBlock [CatchClause]
  | LineControlLine
  | LineControlSpecified {- lineNum -} Integer {- fileName -} String
  | BuildConfigurationStatement BuildConfiguration [Statement] [BuildConfigurationElseifClause]
                                (Maybe BuildConfigurationElseClause)
  deriving (Show, Eq)

type PatternWhere = (Pattern, Maybe WhereClause)

data Case
  = CaseLabel [PatternWhere] [Statement]
  | CaseDefault [Statement]
  deriving (Show, Eq)

data CatchClause = CatchClause (Maybe Pattern) (Maybe WhereClause) CodeBlock
  deriving (Show, Eq)

data WhereClause = WhereClause Expression
  deriving (Show, Eq)

type LabelName = String

data PlatformName
  = IOS
  | IOSApplicationExtension
  | OSX
  | OSXApplicationExtension
  | WatchOS
  deriving (Show, Eq)

data AvailabilityArgument
  = PlatformAvailabilityArgument PlatformName PlatformVersion
  | PlatformWildcard
  deriving (Show, Eq)

data PlatformVersion = PlatformVersion String
  deriving (Show, Eq)

data Condition
  = CaseCondition Pattern Initializer (Maybe WhereClause)
  | AvailabilityCondition [AvailabilityArgument]
  | OptionalBindingCondition
      OptionalBindingContinuationHead
      OptionalBindingContinuations
      (Maybe WhereClause)
  deriving (Show, Eq)

data ConditionList = ConditionList [Condition]
  deriving (Show, Eq)

data ConditionClause = ConditionClause (Maybe Expression) ConditionList
  deriving (Show, Eq)

data ForInit
  = FiDeclaration Declaration
  | FiExpressionList [Expression]
  deriving (Show, Eq)

data CodeBlock = CodeBlock [Statement]
  deriving (Show, Eq)

type Identifier = String
type Name = Identifier
type TypeAliasName = Name
type StructName = Name
type ClassName = Name
type ProtocolName = Name
type VariableName = Name
type EnumCaseName = Name

data StructType = Struct | Class
  deriving (Show, Eq)

data ProtocolMembers = ProtocolMembers [ProtocolMember]
  deriving (Show, Eq)

data ProtocolMember
  = ProtocolPropertyDeclaration [Attribute] [DeclarationModifier] VariableName TypeAnnotation {- gskb -} GetSetBlock
  | ProtocolMethodDeclaration
      [Attribute]
      [DeclarationModifier]
      FunctionName
      (Maybe GenericParameterClause)
      [[Parameter]]
      (Maybe String) -- "throws" or "rethrows" -- FIXME
      (Maybe FunctionResult)
  | ProtocolInitializerDeclaration
      [Attribute]
      [DeclarationModifier]
      InitKind
      (Maybe GenericParameterClause)
      [Parameter]
      String -- throwsDecl
  | ProtocolSubscriptDeclaration
      [Attribute]
      [DeclarationModifier]
      [Parameter] -- ParameterClause
      [Attribute] -- Result attributes
      Type -- result type
      GetSetBlock -- gskb
  | ProtocolAssociatedTypeDeclaration
      [Attribute]
      (Maybe DeclarationModifier)
      TypeAliasName
      (Maybe TypeInheritanceClause)
      (Maybe Type)
  deriving (Show, Eq)

data Declaration
  = ImportDeclaration [Attribute] (Maybe ImportKind) ImportPath
  | DeclVariableDeclaration VariableDeclaration
  | ConstantDeclaration [Attribute] [DeclarationModifier] [PatternInitializer]
  | TypeAlias [Attribute] (Maybe DeclarationModifier) TypeAliasName Type
  | FunctionDeclaration
    { funAttrs :: [Attribute]
    , funDecls :: [DeclarationModifier]
    , funName :: FunctionName
    , funGenericParamClause :: Maybe GenericParameterClause
    , funParameterClauses :: [[Parameter]]
    , funThrowDecl :: Maybe String -- "throws" or "rethrows" -- FIXME
    , funResult :: Maybe FunctionResult
    , funBody :: Maybe CodeBlock
    }
  | EnumDeclaration EnumDeclaration
  | StructDeclaration
      StructType
      [Attribute]
      (Maybe DeclarationModifier)
      StructName
      (Maybe GenericParameterClause)
      (Maybe TypeInheritanceClause)
      [Declaration]
  | InitializerDeclaration
      [Attribute]
      [DeclarationModifier]
      InitKind
      (Maybe GenericParameterClause)
      [Parameter]
      String -- throwsDecl
      CodeBlock
  | DeinitializerDeclaration
      [Attribute]
      CodeBlock
  | ExtensionDeclaration
      (Maybe DeclarationModifier)
      TypeIdentifier
      (Maybe TypeInheritanceClause)
      ExtensionBody
  | SubscriptDeclaration
      [Attribute]
      [DeclarationModifier]
      [Parameter] -- ParameterClause
      [Attribute] -- Result attributes
      Type -- result type
      SubscriptBlock
  | OperatorDeclaration OperatorDecl
  | ProtocolDeclaration
      [Attribute]
      (Maybe DeclarationModifier)
      ProtocolName
      (Maybe TypeInheritanceClause)
      ProtocolMembers
  deriving (Show, Eq)

data SubscriptBlock
  = SubscriptCodeBlock CodeBlock
  | SubscriptGetSetBlock GetSetBlock
  deriving (Show, Eq)

data ExtensionBody = ExtensionBody [Declaration]
  deriving (Show, Eq)

data VariableDeclaration
  = VarDeclPattern [Attribute] [DeclarationModifier] [PatternInitializer]
  | VarDeclReadOnly [Attribute] [DeclarationModifier] VarName TypeAnnotation CodeBlock
  | VarDeclGetSet [Attribute] [DeclarationModifier] VarName TypeAnnotation GetSetBlock
  | VarDeclObserved [Attribute] [DeclarationModifier] VarName (Maybe TypeAnnotation) (Maybe Initializer) ObservedBlock
  deriving (Show, Eq)

data ObservedBlock = ObservedBlock -- aka WillSetDidSetBlock
  deriving (Show, Eq)

type IsIndirect = Bool
type EnumName = Identifier
type VarName = Identifier
type AttributeName = Identifier

type ClassRequirement = Bool

data TypeInheritanceClause = TypeInheritanceClause ClassRequirement [TypeIdentifier]
  deriving (Show, Eq)

data EnumDeclaration
  = UnionEnum
      [Attribute]
      (Maybe DeclarationModifier)
      IsIndirect
      EnumName
      (Maybe GenericParameterClause)
      (Maybe TypeInheritanceClause)
      [UnionStyleEnumMember]
  | RawEnumDeclaration
      [Attribute]
      (Maybe DeclarationModifier)
      EnumName
      (Maybe GenericParameterClause)
      TypeInheritanceClause
      RawValueEnumMembers
  deriving (Show, Eq)

type CaseName = String

data UnionStyleEnumMember
    = EnumMemberDeclaration Declaration
    | EnumMemberCase [Attribute] IsIndirect [(CaseName, Maybe {-Tuple-} Type)]
  deriving (Show, Eq)

data DeclarationModifier
  = Modifier String
  | AccessLevelModifier String
  deriving (Show, Eq)

type Throws = String -- "throws", "rethrows", "" -- FIXME

data InOut = InOut
  deriving (Show, Eq)

type ElementName = Name

data TupleElementType
  = TupleElementTypeAnon [Attribute] (Maybe InOut) Type
  | TupleElementTypeNamed (Maybe InOut) ElementName TypeAnnotation
  deriving (Show, Eq)

data TupleTypeBody = TupleTypeBody [TupleElementType] Bool
  deriving (Show, Eq)

data Type
  = TypeIdentifierType TypeIdentifier
  | TypeOpt Type
  | ImplicitlyUnwrappedOptType Type
  | ArrayType Type
  | DictionaryType Type Type
  | FunctionType Throws Type Type
  | TypeMetaType Type
  | ProtocolMetaType Type
  | ProtocolCompositionType [ProtocolIdentifier]
  | TupleType (Maybe TupleTypeBody)
  deriving (Show, Eq)

type ProtocolIdentifier = TypeIdentifier
type ImportPath = [ImportPathIdentifier]
type ImportKind = String

data ImportPathIdentifier
  = ImportIdentifier String
  | ImportOperator String
  deriving (Show, Eq)

data PatternInitializer = PatternInitializer Pattern (Maybe Initializer)
  deriving (Show, Eq)

type OptTypeAnnotation = Maybe TypeAnnotation

data Pattern
  = WildcardPattern OptTypeAnnotation
  | IdentifierPattern Identifier OptTypeAnnotation
  | OptionalPattern Identifier -- id?
  | TuplePattern [Pattern] OptTypeAnnotation
  | ExpressionPattern Expression
  | VarPattern Pattern
  | LetPattern Pattern
  | IsPattern Type
  | AsPattern Type
  deriving (Show, Eq)

data FunctionResult = FunctionResult [Attribute] Type
  deriving (Show, Eq)

data FunctionName
  = FunctionNameIdent String
  | FunctionNameOp String
  deriving (Show, Eq)

data GenericParameterClause = GenericParameterClause [GenericParameter] (Maybe GenericRequirementClause)
  deriving (Show, Eq)

data GenericParameter
  = GenericParamName TypeName
  | GenericParamTypeId TypeName TypeIdentifier
  | GenericParamProtocol TypeName {- protocol-composition-type -} Type
  deriving (Show, Eq)

data TypeRequirement
 = ConformanceRequirementRegular TypeIdentifier TypeIdentifier
 | ConformanceRequirementProtocol TypeIdentifier {- protocol-composition-type -} Type
 | SameTypeRequirement TypeIdentifier Type
  deriving (Show, Eq)

data GenericRequirementClause = GenericRequirementClause [TypeRequirement]
  deriving (Show, Eq)

data Parameter
  = ParameterLet (Maybe String) String TypeAnnotation (Maybe Expression)
  | ParameterVar (Maybe String) String TypeAnnotation (Maybe Expression)
  | ParameterInOut (Maybe String) String TypeAnnotation
  | ParameterDots (Maybe String) String TypeAnnotation
  deriving (Show, Eq)

data TypeAnnotation = TypeAnnotation [Attribute] Type
  deriving (Show, Eq)

data BuildConfigurationElseifClause = BuildConfigurationElseifClause BuildConfiguration [Statement]
  deriving (Show, Eq)

data BuildConfigurationElseClause = BuildConfigurationElseClause [Statement]
  deriving (Show, Eq)

data BuildConfiguration
  = OperatingSystemTest String
  | ArchitectureTest String
  | BuildConfigurationId String
  | BuildConfigurationBool Literal
  | BuildConfigurationNegate BuildConfiguration
  | BuildConfigurationOr BuildConfiguration BuildConfiguration
  | BuildConfigurationAnd BuildConfiguration BuildConfiguration
  deriving (Show, Eq)

data InitKind
  = Init
  | InitOption
  | InitForce
  deriving (Show, Eq)

data TypeIdentifier = TypeIdentifier [(TypeName, [Type])]
  deriving (Show, Eq)

type TypeName = Identifier

data GetterClause = GetterClause [Attribute] CodeBlock
  deriving (Show, Eq)

data SetterClause = SetterClause [Attribute] (Maybe Identifier) CodeBlock
  deriving (Show, Eq)

data GetSetBlock
  = GetSetBlock CodeBlock
  | GetSet (Maybe GetterClause) (Maybe SetterClause)
  deriving (Show, Eq)

type Op = String
type PrecedenceLevel = Int
data Associativity = AssocLeft | AssocRight | AssocNone
  deriving (Show, Eq)

data OperatorDecl
  = PrefixOperatorDecl Op
  | PostfixOperatorDecl Op
  | InfixOperatorDecl Op (Maybe PrecedenceLevel) (Maybe Associativity)
  deriving (Show, Eq)

data Attribute = Attribute AttributeName (Maybe String)
  deriving (Show, Eq)

data Initializer = Initializer Expression
  deriving (Show, Eq)

data OptionalBindingContinuationHead
  = LetOptionalBinding Pattern Initializer
  | VarOptionalBinding Pattern Initializer
  deriving (Show, Eq)

data OptionalBindingContinuations = OptionalBindingContinuations [OptionalBindingContinuation]
  deriving (Show, Eq)

data OptionalBindingContinuation
  = OptionalBindingContinuationPattern Pattern Initializer
  | OptionalBindingContinuationHead OptionalBindingContinuationHead
  deriving (Show, Eq)

data RawValueEnumCase = RawValueEnumCase EnumCaseName (Maybe Literal)
  deriving (Show, Eq)

data RawValueEnumCases = RawValueEnumCases [RawValueEnumCase]
  deriving (Show, Eq)

data RawValueEnumMember
  = RawValueEnumCaseClause [Attribute] RawValueEnumCases
  | RawValueEnumDeclaration Declaration
  deriving (Show, Eq)

data RawValueEnumMembers = RawValueEnumMembers [RawValueEnumMember]
  deriving (Show, Eq)
