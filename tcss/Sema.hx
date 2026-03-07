package tcss;

import tcss.Expr;
import tcss.Type;

typedef ImportFunc = (rawPath:String) -> Module;

class Sema
{
	public var types:Map<String, TCssType> = [];
	public var typeImpls:Map<String, Definition> = [];
	public var errors:Array<Error> = [];
	public var enableRecovery:Bool = false;

	public function new() {}

	public function analyze(module:Module, importModule:ImportFunc):TypedAST
	{
		final ast:TypedAST = [];

		types.clear();
		typeImpls.clear();
		errors = [];

		types['std.dynamic'] = TStdType(TDynamic);
		types['std.enum'] = TStdType(TEnum(null));
		types['std.int'] = TStdType(TInt);
		types['std.float'] = TStdType(TFloat);
		types['std.color'] = TStdType(TColor);
		types['std.unit'] = TStdType(TDynamic);

		registerModule(module, ast, importModule);

		validateInheritance();

		validateTypes();

		buildFinalAST(ast);

		return ast;
	}

	function registerModule(module:Module, ast:TypedAST, importModule:ImportFunc):Void
	{
		for (def in module)
		{
			switch (def.kind)
			{
				case DImport(path, isUrl):
					if (!isUrl)
						registerModule(importModule(path), ast, importModule);
				case DExtern(name, value):
					types[name] = TExtern(new TCssExtern(name, {t: value, pos: def.contentPos}));
					typeImpls[name] = def;

				case DRule(name, fields):
					types[name] = TRule(new TCssRule(name, fields));
					typeImpls[name] = def;

				case DAbstract(name, fields):
					types[name] = TAbstract(new TCssAbstract(name, fields));
					typeImpls[name] = def;
				case DClass(name, parent, fields):
					types[name] = TClass(new TCssClass(name, parent ?? 'root', fields));
					typeImpls[name] = def;
				case DExternCss(content):
					ast.push(TRawCssNode(content));
			}
		}
	}

	function validateInheritance():Void
	{
		for (name => type in types)
		{
			switch (type)
			{
				case TClass(c):
					final parent = getTypeFromString(c.parentName ?? 'root');

					switch (parent)
					{
						case TRule(r), TClass(r):
							c.parent = r;
						case TAbstract(a):
							c.parent = a;
							checkAbstractImplementations(c, cast c.parent);
						default:
							throw 'Error: ${c.parentName} cannot be a parent';
					}
				default:
					continue;
			}
		}
	}

	private function checkAbstractImplementations(child:TCssClass, parent:TCssAbstract):Void
	{
		for (pField in parent.fields)
		{
			var isAbstract = pField.access.contains(AAbstract);

			if (isAbstract)
			{
				var implemented = false;
				for (cField in child.fields)
				{
					switch [pField.kind, cField.kind]
					{
						case [FVar(pn, _, _, _), FVar(cn, _, _, _)] if (pn == cn):
							implemented = true;
							break;
						default:
					}
				}
				if (!implemented)
				{
					var fieldName = switch (pField.kind)
					{
						case FVar(n, _, _, _): n.t;
						default: "unknown";
					};
					throw 'Error: Class ${child.name} must implement abstract field $fieldName from ${parent.name}';
				}
			}
		}
	}

	function validateTypes()
	{
		for (type in types)
		{
			switch (type)
			{
				case TExtern(e):
					checkType(e.value.t, e.value.pos);
				case TRule(r):
					checkFields(r.fields);
				case TAbstract(a):
					checkFields(a.fields);
				case TClass(c):
					checkFields(c.fields);
				case TStdType(t):
			}
		}
	}

	function checkType(t:TypeNode, ?pos:Pos):Void
	{
		if (!types.exists(typeToString(t)))
		{
			error(EUnknownType(t, pos));
		}
	}

	inline function getType(type:TypeNode):TCssType
	{
		checkType(type);

		return getTypeFromString(typeToString(type));
	}

	function getTypeFromString(typeName:String):Null<TCssType>
	{
		return types[typeName];
	}

	function checkFields(fields:Array<Field>):Void
	{
		for (field in fields)
		{
			switch (field.kind)
			{
				case FVar(name, type, value, isDefault):
					checkType(type.t, type.pos);

					if (value != null)
						switch (type.t)
						{
							case TPath(path):
								final t = getType(type.t);
								if (t != null) unify(value, t);
							default:
						}
				default:
			}
		}
	}

	function unify(expr:Expr, type:TCssType):Void
	{
		final e:ExprDef = expr?.expr;

		final type = followType(type);

		final valid:Bool = switch (type)
		{
			case TStdType(t):
				switch (t)
				{
					case TInt: e.match(EConst(CInt(_, null)));
					case TFloat: e.match(EConst(CFloat(_, null)));
					case TColor: e.match(EConst(CColor(_)));
					case TUnit(types, units):
						var valid:Bool = false;

						switch (e)
						{
							case EConst(c = CInt(_, unit)) | EConst(c = CFloat(_, unit)):
								final isInt = c.match(CInt(_));

								var typeAllowed:Bool = false;

								for (t in types)
								{
									var follow = followType(t);
									typeAllowed = typeAllowed
										|| if (isInt) follow.match(TStdType(TInt)) else follow.match(TStdType(TFloat));

									if (typeAllowed)
										break;
								}

								if (typeAllowed)
								{
									if (!units.contains(unit))
									{
										error(EUnitMismatch({t: unit, pos: expr}, units));
									}
									valid = true;
								}

							default:
						}

						valid;
					case TDynamic: true;
					case TIdent(id):
						switch (e)
						{
							case EId(i) if (i == id): true;
							default: false;
						}
					case TEnum(values):
						final id = switch (e)
						{
							case EId(id): id;
							default: null;
						}

						var match = false;

						for (value in values)
						{
							switch (value)
							{
								case TStdType(TIdent(i)) if (i == id):
									match = true;
								default:
							}
						}

						match;
				}
			case _:
				false;
		}

		if (!valid)
			error(ETypeMismatch(type, expr));
	}

	function followType(type:TCssType):TCssType
	{
		return switch (type)
		{
			case TExtern(e):
				switch (e.value.t)
				{
					case TPath(_):
						followType(getType(e.value.t));
					case TUnit(path, types, units):
						final types = types.map(node -> getType(node));
						final units = units.map(unit -> unit.t);

						TStdType(TUnit(types, units));
					case TEnum('std.enum', values):
						TStdType(TEnum(values.map(node -> TStdType(TIdent(typeToString(node))))));
					case TEnum(path, values):
						TStdType(TEnum(values.map(node -> getType(node))));
				}
			default:
				type;
		}
	}

	function buildFinalAST(ast:TypedAST):TypedAST
	{
		for (type in types)
		{
			switch (type)
			{
				case TClass(c):
					final selectors = ["." + c.name];
					final body:Array<RuleContent> = [];

					fillFields(c, body);

					ast.push(TRuleNode(selectors, body));
				default:
			}
		}
		return ast;
	}

	function fillFields(rule:TCssRule, body:Array<RuleContent>):Void
	{
		if (rule is TCssClass)
		{
			final parent = cast(rule, TCssClass).parent;
			if (parent != null)
				fillFields(parent, body);
		}

		for (f in rule.fields)
		{
			switch (f.kind)
			{
				case FVar(name, type, value, isDefault) if (value != null):
					body.push(Field(name.t, getType(type.t), exprToString(value), false));
				case FExternCss(content):
					body.push(Raw(content.t));
				default:
			}
		}
	}

	public function exprToString(e:Expr):String
	{
		return switch (e.expr)
		{
			case EConst(c):
				switch (c)
				{
					case CInt(v, u): v + (u != null ? u : "");
					case CFloat(v, u): v + (u != null ? u : "");
					case CString(v): '"' + v + '"';
					case CColor(c): c;
				}
			case EId(id): id;
			case EField(expr, field): exprToString(expr) + '.' + field;
			default: throw e.expr;
		}
	}

	public function typeToString(t:TypeNode):String
	{
		return switch (t)
		{
			case TPath(path), TEnum(path, _), TUnit(path, _, _): path;
		}
	}

	public function tcssTypeToString(t:TCssType):String
	{
		return switch (t)
		{
			case TStdType(t):
				switch (t)
				{
					case TInt: 'std.int';
					case TFloat: 'std.float';
					case TColor: 'std.color';
					case TUnit(types, units):
						final typeList = types.map(type -> tcssTypeToString(type));

						'std.unit<${typeList.join(' | ')}, ${units.join(' | ')}>';
					case TDynamic: 'std.dynamic';
					case TIdent(id): '$id';
					case TEnum(values): 'std.enum<' + values.map(t -> tcssTypeToString(t)).join(' | ') + '>';
				}
			case TExtern(e): e.name;
			case TRule(r), TAbstract(r), TClass(r): r.name;
		}
	}

	function error(error:Error):Void
	{
		if (enableRecovery)
		{
			errors.push(error);
			return;
		}

		throw error;
	}
}
