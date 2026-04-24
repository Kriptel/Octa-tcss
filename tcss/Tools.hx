package tcss;

import haxe.iterators.StringKeyValueIterator;
import tcss.Type;
import tcss.Expr;

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

	inline public static function getRule<T:TCssRule>(type:Null<TCssType>):Null<T>
	{
		return switch (type)
		{
			case null:
				return null;
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

	public static function isWithin(offset:Int, pos:Pos):Bool
	{
		return offset >= pos.min && offset <= pos.max;
	}

	public static function combinePos(start:Pos, end:Pos):Null<Pos>
	{
		if (start.file != end.file)
			return null;

		return {
			min: start.min,
			max: end.max,
			line: start.line,
			char: start.char,
			endLine: end.endLine,
			endChar: end.endChar,
			file: start.file
		}
	}

	public static function findFieldInRule(rule:TCssRule, fieldName:String):Null<Field>
	{
		for (f in rule.fields)
		{
			switch (f.kind)
			{
				case FVar(n, _, _, _) if (n.t == fieldName):
					return f;
				default:
			}
		}

		if (rule is TCssClass)
		{
			final parent = cast(rule, TCssClass).parent;
			if (parent != null)
				return findFieldInRule(parent, fieldName);
		}

		return null;
	}

	public static function escapeIdent(ident:String):String
	{
		final s = new StringBuf();

		for (i => c in new StringKeyValueIterator(ident))
		{
			if (c >= '0'.code && c <= '9'.code && (i == 0 || ident.charCodeAt(0) == '-'.code))
			{
				s.add("\\" + StringTools.hex(c) + " ");
				continue;
			}
			else
				if ((c >= 'A'.code && c <= 'Z'.code) || (c >= 'a'.code && c <= 'z'.code) || (c >= '0'.code && c <= '9'.code) || c == '_'.code || c == '-'.code || (i == 0 && (c == '.'.code || c == ':'.code)))
			{
				s.addChar(c);
			}
			else
			{
				s.add('\\');
				s.addChar(c);
			}
		}

		return s.toString();
	}
}
