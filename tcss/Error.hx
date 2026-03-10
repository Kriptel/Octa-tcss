package tcss;

import tcss.Expr;
import tcss.Lexer.Token;

enum Error
{
	EUnexpectedChar(char:Int);
	EUnexpectedToken(tk:Token);
	EUnexpectedExpr(e:Expr);
	EIncomplete(kind:IncompleteKind, ?pos:Pos);
	EUnknownType(type:TypeNode, ?pos:Pos);
	ETypeMismatch(type:Loc<TypeNode>, expr:Expr);
	ESemaError(info:String, ?pos:Pos);
}

enum IncompleteKind
{
	IType;
	IField;
	IExpr(expectedType:TypeNode);
	IRawCss;
	ISemicolon;
}
