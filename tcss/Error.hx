package tcss;

import tcss.Type.TCssType;
import tcss.Expr;
import tcss.Lexer.Token;

enum Error
{
	EUnexpectedChar(char:Int);
	EUnexpectedToken(tk:Token);
	EIncomplete(kind:IncompleteKind, ?pos:Pos);
	EUnknownType(type:TypeNode, ?pos:Pos);
	ETypeMismatch(type:TCssType, expr:Expr);
	EUnitMismatch(unit:Loc<String>, expectedUnits:Array<String>);
}

enum IncompleteKind
{
	IType;
	IField;
	IExpr(expectedType:TypeNode);
	IRawCss;
	ISemicolon;
}
