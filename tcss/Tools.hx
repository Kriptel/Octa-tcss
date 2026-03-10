package tcss;

import tcss.Type;
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

	inline public static function getRule<T:TCssRule>(type:TCssType):Null<T>
	{
		return switch (type)
		{
			case TRule(c) | TStruct(c) | TAbstract(c) | TClass(c):
				cast c;
			default:
				null;
		}
	}

	public static function matchTypes(t1:TCssType, t2:TCssType):Bool
	{
		if (t1.equals(t2))
			return true;

		return switch ([t1, t2])
		{
			case [TStdType(t), TStdType(t2)]:
				switch ([t, t2])
				{
					case [TEnum(type, values), TEnum(type2, values2)]:
						if (!matchTypes(type, type2))
							return false;

						arrayEq(values, values2, (v, v2) -> matchTypes(v, v2));
					case [TUnit(types, units), TUnit(types2, units2)]:
						if (!arrayEq(types, types2, (t, t2) -> matchTypes(t, t2)))
							return false;

						arrayEq(units, units2, (v, v2) -> v == v2);
					default:
						t.equals(t2);
				}
			case [TExtern(e), TExtern(e2)] if (e == e2):
				true;
			case [
				TRule(r) | TAbstract(r) | TStruct(r) | TClass(r),
				TRule(r2) | TAbstract(r2) | TStruct(r2) | TClass(r2)
			] if (r == r2):
				true;
			default:
				false;
		}
	}

	@:generic
	private static function arrayEq<T>(a:Array<T>, b:Array<T>, f:(T, T) -> Bool):Bool
	{
		if (a == b)
			return true;
		if ((a == null || b == null) || a.length != b.length)
			return false;

		for (i in 0...a.length)
		{
			if (!f(a[i], b[i]))
				return false;
		}

		return true;
	}
}
