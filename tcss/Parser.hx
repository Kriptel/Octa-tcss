package tcss;

import tcss.Expr;
import tcss.Lexer;

enum Suggestion
{
	SField;
	SType;
	SFieldName(t:TypeNode);
	SExpr(t:TypeNode);
}

enum Eof
{
	Eof;
}

class Parser
{
	public var enableRecovery:Bool = false;
	public var errors:Array<Error>;
	public var cursorPos:Null<Int>;
	public var suggestion:Null<Suggestion> = null;

	var tokens:Array<Token>;
	var file:String;

	var pos:Int;

	public function new() {}

	inline function getToken():Token
	{
		return tokens[pos++];
	}

	inline function getCurToken()
	{
		return tokens[pos - 1];
	}

	inline function getNextToken()
	{
		return tokens[pos];
	}

	inline function back()
	{
		pos--;
	}

	public function parse(file:String, tokens:Array<Token>, ?cursorPos:Int = null):Module
	{
		this.pos = 0;
		this.tokens = tokens;
		this.file = file;
		this.errors = [];
		this.cursorPos = cursorPos;
		this.suggestion = null;
		final defs:Module = [];

		try
		{
			while (true)
			{
				var t = getToken();

				function addDefinition(k:DefinitionKind, namePos:Pos, ?contentPos:Pos)
				{
					defs.push(
						{
							kind: k,
							namePos: namePos,
							contentPos: contentPos,
							declPos:
								{
									min: t.s,
									max: getCurToken().e,
									line: t.l,
									char: t.c,
									endLine: t.el,
									endChar: t.ec,
									file: file
								}
						});
				}

				switch (t.t)
				{
					case TId(id):
						switch (id)
						{
							case 'import':
								switch (getToken().t)
								{
									case TId(id):
										addDefinition(DImport(id, false), getCurToken().pos);
									case TUrl(url):
										addDefinition(DImport(url, true), getCurToken().pos);
									default:
										error(EUnexpectedToken(getCurToken()));
								}

								ensure(TSemicolon);
							case 'extern':
								final id = getIdent();

								switch (id.t)
								{
									case 'rule':
										final typeName = getIdent();
										final fields = parseFields();

										addDefinition(DRule(typeName.t, fields.t), typeName.pos, fields.pos);
									case 'css':
										switch (getToken().t)
										{
											case TRaw(raw):
												addDefinition(DExternCss(raw), null, getCurToken().pos);
											default:
												error(EUnexpectedToken(getCurToken()));
										}
									default:
										ensure(TOp('='));

										final type = parseType();

										addDefinition(DExtern(id.t, type.t), id.pos, type.pos);

										ensure(TSemicolon);
								}
							default:
								error(EUnexpectedToken(t));
							case 'struct':
								final typeName = getIdent();

								final fields = parseFields();

								addDefinition(DStruct(typeName.t, fields.t), typeName.pos, fields.pos);

							case 'abstract':
								final typeName = getIdent();

								final fields = parseFields();

								addDefinition(DAbstract(typeName.t, fields.t), typeName.pos, fields.pos);
							case 'class':
								final typeName = getIdent();

								var extend:String = null;

								if (maybe(TId('extends')))
									extend = getIdent().t;

								final fields = parseFields();

								addDefinition(DClass(typeName.t, extend, fields.t), typeName.pos, fields.pos);
							case 'collection':
								ensure(TId('class'));

								switch (getToken().t)
								{
									case TId(id):
										var types:Array<Loc<String>> = [
											{
												t: id,
												pos: getCurToken().pos
											}
										];

										while (maybe(TComma))
											types.push(getIdent());

										ensure(TId('extends'));

										final parent:String = getIdent().t;

										final fields = parseFields();
										for (type in types)
											addDefinition(DClass(type.t, parent, fields.t), type.pos, fields.pos);
									case TBOpen:
										var types:Array<{t:Loc<String>, p:String}> = [];

										while (true)
										{
											var typeName = getIdent();
											ensure(TDoubleDot);
											var parent = getIdent();

											types.push({t: typeName, p: parent.t});

											if (maybe(TBClose))
												break;

											ensure(TComma);
										}

										final fields = parseFields();

										for (t in types)
											addDefinition(DClass(t.t.t, t.p, fields.t), t.t.pos, fields.pos);
									default:
										error(EUnexpectedToken(getCurToken()));
								}
						}
					case TEof:
						break;
					default:
						error(EUnexpectedToken(t));
				}
			}
		} catch (e:Eof) {}

		return defs;
	}

	function parseFields():Loc<Array<Field>>
	{
		ensure(TBrOpen);

		final fields:Array<Field> = [];

		var pos:Pos = getCurToken().pos;

		while (true)
		{
			if (isCursorInGap())
			{
				suggestion = SField;
			}

			var tk = getToken();

			switch (tk.t)
			{
				case TBrClose:
					pos.max = tk.e - 1;
					pos.min += 1;
					break;
				default:
					back();
			}

			if (enableRecovery)
			{
				var fieldList:Null<Array<Field>> = try
				{
					parseField();
				} catch (e:Error)
				{
					null;
				}

				if (fieldList != null)
					for (field in fieldList)
						fields.push(field);
				else
				{
					error(EUnexpectedToken(getToken()));
				}
			}
			else
				for (field in parseField())
					fields.push(field);
		}

		return {
			t: fields,
			pos: pos
		}
	}

	function parseField():Array<Field>
	{
		final access:Array<FieldAccess> = [];

		if (isIncomplete())
		{
			error(EIncomplete(IField));
			return null;
		}

		while (true)
		{
			var id = getIdent();

			switch (id?.t)
			{
				case 'abstract':
					if (access.contains(AAbstract))
						error(EUnexpectedToken(getCurToken()))
					else
						access.push(AAbstract);
				case 'virtual':
					if (access.contains(AVirtual))
						error(EUnexpectedToken(getCurToken()))
					else
						access.push(AVirtual);
				case 'custom':
					if (access.contains(ACustom))
						error(EUnexpectedToken(getCurToken()))
					else
						access.push(ACustom);
				case 'public':
					if (access.contains(APublic))
						error(EUnexpectedToken(getCurToken()))
					else
						access.push(APublic);
				case 'extern':
					if (maybe(TId('css')))
					{
						var next = getToken();
						switch (next.t)
						{
							case TRaw(content):
								final curTkPos = getCurToken().pos;
								final idPos:Pos = id.pos;

								return [
									{
										pos:
											{
												min: idPos.min,
												max: curTkPos.max,
												line: idPos.line,
												char: idPos.char,
												endLine: curTkPos.endLine,
												endChar: curTkPos.endChar,
												file: file
											},
										kind: FExternCss({t: content, pos: curTkPos}),
										access: access
									}
								];
							case TEof:
								error(EIncomplete(IRawCss));
								return null;
							default:
								error(EUnexpectedToken(next));
								return null;
						}
					}
					back();

				default:
					back();

					final type = parseType();

					if (type == null)
					{
						error(EIncomplete(IType));

						return null;
					}

					if (isCursorInGap())
					{
						suggestion = SFieldName(type.t);
					}

					final tk = getToken();

					final nameLocs:Array<Loc<String>> = [];
					switch (tk.t)
					{
						case TId(id):
							nameLocs.push({t: id, pos: tk.pos});
						case TBrOpen:
							nameLocs.push(getIdent());

							while (maybe(TComma))
							{
								nameLocs.push(getIdent());
							}

							ensure(TBrClose);
						default:
							error(EUnexpectedToken(tk));
					}

					if (nameLocs == null)
					{
						error(EIncomplete(IField));
						return null;
					}

					var isDefault:Bool = false;
					var value:Expr = null;

					if (maybe(TOp('=')))
					{
						if (isCursorInGap())
						{
							suggestion = SExpr(type.t);
						}

						if (isIncomplete() || isSemicolon())
						{
							error(EIncomplete(IExpr(type.t)));
							return null;
						}
						isDefault = maybe(TId('default'));
						value = parseExpr();
					}

					if (!value?.expr.match(EObject(_)) && !maybe(TSemicolon))
					{
						error(EIncomplete(ISemicolon));
					}

					return [
						for (nameLoc in nameLocs)
						{
							final curTk = getCurToken();
							{
								pos:
									{
										min: id.pos.min,
										max: curTk.e,
										line: id.pos.line,
										char: id.pos.char,
										endLine: curTk.el,
										endChar: curTk.ec,
										file: file
									},
								kind: FVar(nameLoc, type, value, isDefault),
								access: access
							}
						}
					];
			}
		}
	}

	function parseType():Null<Loc<TypeNode>>
	{
		var tk = getToken();

		switch (tk.t)
		{
			case TId(id):
				if (maybe(TLt))
				{
					var firstType = parseType();
					if (firstType == null)
					{
						error(EIncomplete(IType));
						return null;
					}

					final enums:Array<TypeNode> = [firstType.t];

					while (maybe(TOp('|')))
					{
						var nextType = parseType();
						if (nextType != null)
							enums.push(nextType.t);
					}

					var units:Array<Loc<String>> = null;

					if (maybe(TComma))
					{
						units = [getUnit()];
						while (maybe(TOp('|')))
						{
							units.push(getUnit());
						}
					}

					ensure(TMt);

					final curTk = getCurToken();
					return {
						t: units != null ? TUnit(id, enums, units) : TEnum(id, enums),
						pos:
							{
								min: tk.e,
								max: curTk.e,
								line: tk.l,
								char: tk.c,
								endLine: curTk.el,
								endChar: curTk.ec,
								file: file
							}
					};
				}

				return {
					t: TPath(id),
					pos: tk.pos
				};

			case TEof:
				back();
				return null;

			default:
				error(EUnexpectedToken(tk));
				return null;
		}
	}

	function parseExpr():Expr
	{
		var tk = getToken();

		switch (tk.t)
		{
			case TId(id):
				if (StringTools.contains(id, '.'))
				{
					final ids = id.split('.');

					var e = makeExpr(EId(ids.shift()), tk.s, tk.e, tk.l, tk.c, tk.el, tk.ec);

					for (i in ids)
					{
						if (i == '')
						{
							error(EUnexpectedToken(tk));
							return null;
						}

						e = parseExprNext(makeExpr(EField(e, i), tk.s, tk.e, tk.l, tk.c, tk.el, tk.ec));
					}

					return parseExprNext(e);
				}

				return parseExprNext(makeExpr(EId(id), tk.s, tk.e, tk.l, tk.c, tk.el, tk.ec));
			case TColor(color):
				return parseExprNext(makeExpr(EConst(CColor(color)), tk.s, tk.e, tk.l, tk.c, tk.el, tk.ec));
			case TInt(i):
				return parseExprNext(makeExpr(EConst(CInt(i, null)), tk.s, tk.e, tk.l, tk.c, tk.el, tk.ec));
			case TFloat(f):
				return parseExprNext(makeExpr(EConst(CFloat(f, null)), tk.s, tk.e, tk.l, tk.c, tk.el, tk.ec));
			case TString(s):
				return parseExprNext(makeExpr(EConst(CString(s)), tk.s, tk.e, tk.l, tk.c, tk.el, tk.ec));
			case TBrOpen:
				back();
				return parseExprNext(makeExpr(EObject(parseFields()), tk.s, getCurToken().e, tk.l, tk.c, tk.el, tk.ec));
			default:
				error(EUnexpectedToken(tk));
		}

		return null;
	}

	function parseExprNext(e:Expr):Expr
	{
		var tk = getToken();

		switch (tk.t)
		{
			case TDot:
				final fieldId = getIdent().t;
				final curTk = getCurToken();
				return parseExprNext(makeExpr(EField(e, fieldId), e.min, curTk.e, e.line, e.char, curTk.el, curTk.ec));
			case TOp('|'):
				final e2:Expr = parseExpr();

				return parseExprNext(makeExpr(EBinop('|', e, e2), e.min, e2.max, e.line, e.char, e2.endLine, e2.endChar));
			case TId(id):
				switch (e.expr)
				{
					case EConst(CInt(i, null)):
						return parseExprNext(makeExpr(EConst(CInt(i, id)), e.min, tk.e, e.line, e.char, tk.el, tk.ec));
					case EConst(CFloat(f, null)):
						return parseExprNext(makeExpr(EConst(CFloat(f, id)), e.min, tk.e, e.line, e.char, tk.el, tk.ec));
					default:
						back();
						return e;
				}
			case TOp('%'):
				switch (e.expr)
				{
					case EConst(CInt(i, null)):
						return parseExprNext(makeExpr(EConst(CInt(i, '%')), e.min, tk.e, e.line, e.char, tk.el, tk.ec));
					case EConst(CFloat(f, null)):
						return parseExprNext(makeExpr(EConst(CFloat(f, '%')), e.min, tk.e, e.line, e.char, tk.el, tk.ec));
					default:
						error(EUnexpectedToken(tk));
				}
			default:
				back();
				return e;
		}
		return null;
	}

	function makeExpr(e:ExprDef, min:Int, max:Int, line:Int, char:Int, endLine:Int, endChar:Int):Expr
	{
		return {
			expr: e,
			min: min,
			max: max,
			line: line,
			char: char,
			endLine: endLine,
			endChar: endChar,
			file: file
		}
	}

	function ensure(tk:TokenDef):Void
	{
		var t = getToken();
		if (!t.t.equals(tk))
			error(EUnexpectedToken(t));
	}

	function maybe(tk:TokenDef):Bool
	{
		var t = getToken();
		if (t.t.equals(tk))
			return true;

		back();
		return false;
	}

	function getIdent():Loc<String>
	{
		var tk = getToken();
		return switch (tk.t)
		{
			case TId(id): {t: id, pos: tk.pos};
			default: error(EUnexpectedToken(tk));
		}
	}

	function getUnit():Loc<String>
	{
		var tk = getToken();
		return switch (tk.t)
		{
			case TId(id): {t: id, pos: tk.pos}
			case TOp('%'): {t: '%', pos: tk.pos}
			default: error(EUnexpectedToken(tk));
		}
	}

	function getIdentSafe():Null<Loc<String>>
	{
		var tk = getToken();
		return switch (tk.t)
		{
			case TId(id): {t: id, pos: tk.pos};
			default:
				back();
				null;
		}
	}

	inline function isIncomplete(?t:Token):Bool
	{
		if (t == null)
			t = getNextToken();
		return t.t == TEof || t.t == TBrClose;
	}

	inline function isSemicolon(?t:Token):Bool
	{
		if (t == null)
			t = getNextToken();
		return t.t == TSemicolon;
	}

	inline function isCursorInGap(?t1:Token, ?t2:Token, ?cursorPos:Int):Bool
	{
		t1 ??= getCurToken();
		t2 ??= getNextToken();

		cursorPos ??= this.cursorPos;

		return cursorPos >= t1.pos.max && cursorPos <= t2.pos.min;
	}

	function error(e:Error):Dynamic
	{
		if (enableRecovery)
		{
			switch (e)
			{
				case EUnexpectedToken({t: TEof}):
					throw Eof;
				case EIncomplete(kind, null):
					errors.push(EIncomplete(kind, getCurToken().pos));
					return null;
				default:
					errors.push(e);
					return null;
			}
		}

		throw e;
	}
}
