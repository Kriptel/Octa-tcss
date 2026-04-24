package tcss;

typedef Loc<T> =
{
	var t:T;
	var pos:Pos;
}

typedef Pos =
{
	var min:Int;
	var max:Int;

	var line:Int;
	var char:Int;
	var endLine:Int;
	var endChar:Int;

	var file:String;
}

typedef Expr = Pos &
{
	var file:String;
	var expr:ExprDef;
}

enum Const
{
	CInt(i:Int, ?unit:String);
	CFloat(f:Float, ?unit:String);
	CString(s:String);
	CColor(color:String);
}

enum ExprDef
{
	EConst(c:Const);
	EId(id:String);
	EBinop(op:String, e1:Expr, e2:Expr);
	EField(obj:Expr, field:String);
	EObject(fields:Loc<Array<Field>>);
}

typedef Module = Array<Definition>;

typedef Definition =
{
	var declPos:Pos;
	var namePos:Pos;
	var contentPos:Pos;

	var kind:DefinitionKind;
}

enum DefinitionKind
{
	DImport(path:String, isUrl:Bool);
	DExtern(name:String, value:TypeNode);
	DRule(name:String, fields:Array<Field>);
	DStruct(name:String, fields:Array<Field>);
	DAbstract(name:String, fields:Array<Field>);
	DClass(name:String, parent:Null<String>, fields:Array<Field>);
	DExternCss(content:String);
}

typedef Field =
{
	var pos:Pos;
	var kind:FieldType;
	var access:Array<FieldAccess>;
}

enum FieldAccess
{
	AVirtual;
	AAbstract;
	ACustom;
	APublic;
}

enum FieldType
{
	FVar(name:Loc<String>, type:Loc<TypeNode>, value:Null<Expr>, isDefault:Bool);
	FExternCss(content:Loc<String>);
}

enum TypeNode
{
	TPath(path:String);
	TEnum(path:String, params:Array<TypeNode>);
	TUnit(path:String, params:Array<TypeNode>, units:Array<Loc<String>>);
}
