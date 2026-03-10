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
		types['std.enum'] = TStdType(TVirtual('std.enum'));
		types['std.one_of'] = TStdType(TVirtual('std.one_of'));
		types['std.zero'] = TStdType(TVirtual('std.zero'));
		types['std.int'] = TStdType(TInt);
		types['std.float'] = TStdType(TFloat);
		types['std.string'] = TStdType(TString);
		types['std.color'] = TStdType(TColor);
		types['std.unit'] = TStdType(TVirtual('std.unit'));

		registerModule(module, ast, importModule);

		unwrapStructs();

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
					types[name] = TRule(new TCssRule(name, fields.copy()));
					typeImpls[name] = def;

				case DAbstract(name, fields):
					types[name] = TAbstract(new TCssAbstract(name, fields.copy()));
					typeImpls[name] = def;

				case DStruct(name, fields):
					types[name] = TStruct(new TCssStruct(name, fields.copy()));
					typeImpls[name] = def;

				case DClass(name, parent, fields):
					types[name] = TClass(new TCssClass(name, parent ?? 'root', fields.copy()));
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

							checkFieldImplementations(c);
						case TAbstract(a):
							c.parent = a;
							checkAbstractImplementations(c, cast c.parent);
						default:
							error(ESemaError('${c.parentName} cannot be a parent'));
					}
				default:
					continue;
			}
		}
	}

	function checkFieldImplementations(c:TCssClass)
	{
		final parentFields:Map<String, Loc<TypeNode>> = [];

		for (f in c.parent.fields)
		{
			switch (f.kind)
			{
				case FVar(name, type, value, isDefault):
					if (parentFields.exists(name.t))
						error(ESemaError('Duplicate declaration of field `${name.t}`', f.pos));

					parentFields[name.t] = type;
				case FExternCss(content):
			}
		}

		for (f in c.fields)
		{
			switch (f.kind)
			{
				case FVar(name, type, value, isDefault):
					if (!parentFields.exists(name.t))
					{
						error(ESemaError('Unknown property `${name.t}`', name.pos));
					}

					final t:TCssType = getType(type.t);
					final parentType:TCssType = followType(getType(parentFields[name.t].t));

					if (!Tools.matchTypes(followType(t), parentType))
					{
						error(ESemaError('`${tcssTypeToString(t)}` should be `${tcssTypeToString(parentType)}`', name.pos));
					}

				case FExternCss(content):
			}
		}
	}

	function checkAbstractImplementations(child:TCssClass, parent:TCssAbstract):Void
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
					error(ESemaError('Error: Class ${child.name} must implement abstract field $fieldName from ${parent.name}'));
				}
			}
		}
	}

	function unwrapStructs()
	{
		for (type in types)
		{
			switch (type)
			{
				case TRule(r), TStruct(r), TAbstract(r), TClass(r):
					unwrapFieldStructs(r);
				default:
			}
		}
	}

	function unwrapFieldStructs(r:TCssRule)
	{
		for (field in r.fields.copy())
		{
			switch (field.kind)
			{
				case FVar(name, type, value, isDefault):
					final struct:TCssStruct = Tools.getRule(followType(getType(type.t)));

					if (struct == null)
						continue;

					final values:Map<String, Expr> = [];

					if (value != null)
						switch (value.expr)
						{
							case EObject(efields):
								for (efield in efields.t)
								{
									switch (efield.kind)
									{
										case FVar(n, _, v, _):
											values[n.t] = v;
										default:
									}
								}
							default:
								error(EUnexpectedExpr(value));
						}

					for (f in struct.fields)
					{
						switch (f.kind)
						{
							case FVar(n, t, v, d):
								final fieldName:String = if (n.t == 'self')
								{
									r.fields.remove(field);
									name.t;
								}
								else
								{
									name.t + '.' + n.t;
								}

								r.fields.push(
									{
										pos: field.pos,
										kind: FVar(
											{
												pos: name.pos,
												t: fieldName
											}, t, values[n.t], isDefault),
										access: field.access
									});
							case FExternCss(content):
						}
					}
				case FExternCss(content):
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
					getType(e.value.t);
				case TRule(r), TStruct(r):
					checkFields(r, false);
				case TAbstract(a):
					checkFields(a);
				case TClass(c):
					checkFields(c);
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

	inline function getType(type:TypeNode, ?pos:Pos):TCssType
	{
		return switch (type)
		{
			case TPath(path):
				checkType(type, pos);

				getTypeFromString(typeToString(type));
			case TEnum(path, params):
				checkType(type, pos);

				switch (followType(getTypeFromString(path)))
				{
					case TStdType(TVirtual('std.enum')):
						TStdType(TEnum(getType(TPath(path)), params.map(t ->
						{
							final id = switch (t)
							{
								case TPath(path): path;
								default: null;
							}

							TStdType(TIdent(id));
						})));
					case t:
						TStdType(TEnum(t, params.map(t -> getType(t))));
				}
			case TUnit(path, params, units):
				checkType(type, pos);

				TStdType(TUnit(params.map(t -> getType(t)), units.map(u -> u.t)));
		}
	}

	function getTypeFromString(typeName:String):Null<TCssType>
	{
		return types[typeName];
	}

	function checkFields(rule:TCssRule, ?allowExprs:Bool = true):Void
	{
		for (field in rule.fields)
		{
			switch (field.kind)
			{
				case FVar(name, type, value, isDefault):
					checkType(type.t, type.pos);

					if (value != null)
					{
						if (!allowExprs)
							error(EUnexpectedExpr(value));

						final valid = unify(value, getType(type.t));

						if (!valid)
							error(ETypeMismatch(type, value));
					}
				default:
			}
		}
	}

	function unify(expr:Expr, type:TCssType):Bool
	{
		if (type == null)
			return false;

		final e:ExprDef = expr?.expr;

		final type = followType(type);

		return switch (type)
		{
			case TStdType(t):
				switch (t)
				{
					case TInt:
						e.match(EConst(CInt(_, null)));
					case TFloat:
						e.match(EConst(CFloat(_, null)));
					case TColor:
						e.match(EConst(CColor(_)));
					case TString:
						e.match(EConst(CString(_)));
					case TUnit(types, units):
						switch (e)
						{
							case EConst(c = CInt(_, unit)) | EConst(c = CFloat(_, unit)):
								final isInt = c.match(CInt(_));

								var typeAllowed:Bool = false;

								for (t in types)
								{
									final follow = followType(t);
									typeAllowed = typeAllowed || if (isInt) follow.match(TStdType(TInt)) else follow.match(TStdType(TFloat));

									if (typeAllowed)
										break;
								}

								if (typeAllowed && units.contains(unit))
								{
									return true;
								}
							default:
						}

						false;
					case TDynamic:
						true;
					case TIdent(id):
						e.equals(EId(id));
					case TEnum(t, values):
						final id = switch (e)
						{
							case EId(id): id;
							default: null;
						}

						switch (t)
						{
							case TStdType(TVirtual('std.enum' | 'std.one_of')):
								for (value in values)
								{
									if (unify(expr, value))
										return true;
								}
							default:
						}

						false;
					case TVirtual('std.zero'):
						e.match(EConst(CInt(0, null))) || e.match(EConst(CFloat(0, null)));
					case TVirtual(id):
						false;
				}
			case _:
				false;
		}
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
					case TEnum(path, values):
						getType(e.value.t);
				}
			case TStdType(TEnum(type, values)):
				TStdType(TEnum(followType(type), values));
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
					case TString: 'std.string';
					case TIdent(id): '$id';
					case TVirtual(id): 'std.virtual($id)';
					case TEnum(t, values):
						tcssTypeToString(t) + '<' + values.map(t -> tcssTypeToString(t)).join(' | ') + '>';
				}
			case TExtern(e): e.name;
			case TRule(r), TStruct(r), TAbstract(r), TClass(r): r.name;
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
