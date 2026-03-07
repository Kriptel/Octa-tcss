package tcss;

import tcss.Expr.Definition;

class Tools
{
	inline public static function getTypeName(def:Definition):Null<String>
	{
		return switch (def.kind)
		{
			case DRule(name, _), DAbstract(name, _), DClass(name, _, _), DExtern(name, _):
				name;
			default: null;
		}
	}

	inline public static function getTypeParent(def:Definition):Null<String>
	{
		return switch (def.kind)
		{
			case DRule(name, _), DAbstract(name, _), DClass(name, _, _):
				name;
			default: null;
		}
	}
}
