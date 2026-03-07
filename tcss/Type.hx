package tcss;

import tcss.Expr;

typedef TypedAST = Array<TypedASTNode>;

enum TypedASTNode
{
	TRuleNode(selectors:Array<String>, body:Array<RuleContent>);
	TAtRuleNode(name:String, params:String, ?block:TypedAST);
	TRawCssNode(css:String);
}

enum RuleContent
{
	Field(field:String, type:TCssType, value:String, important:Bool);
	Variable(name:String, value:String);
	Raw(content:String);
}

enum TCssType
{
	TStdType(t:TCssStdType);
	TExtern(e:TCssExtern);
	TRule(r:TCssRule);
	TAbstract(a:TCssAbstract);
	TClass(c:TCssClass);
}

enum TCssStdType
{
	TInt;
	TFloat;
	TColor;
	TUnit(types:Array<TCssType>, units:Array<String>);
	TDynamic;
	TEnum(values:Array<TCssType>);
	TIdent(id:String);
}

class TCssExtern
{
	public var name:String;
	public var value:Loc<TypeNode>;

	public function new(name:String, value:Loc<TypeNode>)
	{
		this.name = name;
		this.value = value;
	}

	function toString():String
	{
		return 'TCssExtern($name, ${value.t})';
	}
}

class TCssRule
{
	public var name:String;
	public var fields:Array<Field>;

	public function new(name:String, fields:Array<Field>)
	{
		this.name = name;
		this.fields = fields;
	}
}

class TCssAbstract extends TCssRule {}

class TCssClass extends TCssRule
{
	public var parent:TCssRule;
	public var parentName:Null<String>;

	public function new(name:String, parentName:Null<String>, fields:Array<Field>)
	{
		super(name, fields);
		this.parentName = parentName;
	}
}
