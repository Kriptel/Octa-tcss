package tcss;

#if tcss_api
import tcss.Expr;
import tcss.Type;
import tcss.Parser;

using tcss.Tools;

typedef DocumentData =
{
	var ?uri:String;
	var content:String;
}

typedef ErrorData =
{
	info:String,
	pos:Pos
}

typedef CompletionData =
{
	var label:String;
	var kind:CompletionKind;
	var ?insertText:String;
	var ?isSnippet:Bool;
	var ?detail:String;
	var ?documentation:String;
	var ?sortText:String;
}

enum abstract CompletionKind(String)
{
	var CLASS;
	var FIELD;
	var ENUMVALUE;
}

@:expose
class Api
{
	public static final version:String = "1.0.0";

	public static function createEnv(paths:Array<String>, getModulePath:String->String, importFunc:String->DocumentData):Environment
	{
		return new Environment(paths, getModulePath, importFunc);
	}

	public static function analyze(env:Environment, doc:DocumentData):Array<ErrorData>
	{
		var info = try
		{
			env.analyze(doc);
		} catch (e:Dynamic)
		{
			return [];
		}

		final diagnostics:Array<ErrorData> = [];

		for (error in info.errors)
		{
			var message:String = null;
			var pos:Pos = null;
			switch (error)
			{
				case EUnexpectedToken(tk):
					pos = tk.pos;
					message = 'Unexpected token `${tk.t}`';
				case EIncomplete(kind, p):
					pos = p;

					switch (kind)
					{
						case IType:
							message = 'Expected type';
						case IField:
							message = 'Expected field name';
						case IExpr(t):
							message = 'Expected expression (${env.sema.typeToString(t)})';
						case IRawCss:
							message = 'Expected raw css block';
						case ISemicolon:
							message = 'Expected ;';
					}
				case ETypeMismatch(type, expr):
					pos = expr;

					message = '${env.sema.exprToString(expr)} should be ${env.sema.typeToString(type.t)}';

				case EUnknownType(type, p) if (p != null):
					pos = p;
					message = 'Unknown type `${env.sema.typeToString(type)}`';
				case ESemaError(info, p) if (p != null):
					pos = p;
					message = info;
				default:
					continue;
			}

			if (message != null && pos != null)
				diagnostics.push({info: message, pos: pos});
		}

		return diagnostics;
	}

	public static function getHover(env:Environment, doc:DocumentData, offset:Int):Null<String>
	{
		return env.getHover(doc, offset);
	}

	public static function getDefinition(env:Environment, doc:DocumentData, offset:Int):Pos
	{
		return env.getDefinition(doc, offset);
	}

	public static function getCompletions(env:Environment, doc:DocumentData, offset:Int):Array<CompletionData>
	{
		return env.getCompletions(doc, offset);
	}

	public static function generateCss(env:Environment, doc:DocumentData):String
	{
		return env.generateCss(doc);
	}
}

@:keep
class Environment
{
	public var sema:Sema;

	var paths:Array<String>;
	var importFunc:String->DocumentData;
	var parser:Parser;
	var getModulePath:String->String;

	public function new(paths:Array<String>, getModulePath:String->String, importFunc:String->DocumentData)
	{
		this.paths = paths.copy();
		this.importFunc = importFunc;
		this.getModulePath = getModulePath;

		sema = new Sema();
		parser = new Parser();

		sema.enableRecovery = parser.enableRecovery = true;
	}

	function parseModule(doc:DocumentData, ?cursorPos:Int):Module
	{
		return parser.parse(doc.uri, new Lexer(doc.content, doc.uri).tokenize(), cursorPos);
	}

	public function analyze(doc:DocumentData):{ast:tcss.Type.TypedAST, errors:Array<Error>}
	{
		final tokens = new Lexer(doc.content, doc.uri).tokenize();
		final module = parser.parse(doc.uri, tokens);

		final ast = sema.analyze(module, this.importModule);

		var allErrors = parser.errors.concat(sema.errors);
		return {ast: ast, errors: allErrors};
	}

	function importModule(moduleName:String):Module
	{
		final doc:DocumentData = importFunc(moduleName);

		if (doc == null)
			return [];

		final tokens = new Lexer(doc.content, doc.uri).tokenize();
		return new Parser().parse(doc.uri, tokens);
	}

	// Hover

	public function getHover(doc:DocumentData, offset:Int):Null<String>
	{
		final module = parseModule(doc);

		for (def in module)
		{
			if (def.contentPos != null && offset.isWithin(def.contentPos))
			{
				final fieldHover = getFieldHover(def, offset);
				if (fieldHover != null)
					return fieldHover;

				return '*(Inside body of ${getTypeName(def.kind)})*';
			}

			if (offset.isWithin(def.declPos))
			{
				return createTypeHover(def);
			}
		}

		return null;
	}

	function getType(typeName:String):TCssType
	{
		return @:privateAccess sema.getTypeFromString(typeName);
	}

	function getTypeName(kind:DefinitionKind):String
	{
		return switch (kind)
		{
			case DRule(name, _): name;
			case DStruct(name, _): name;
			case DAbstract(name, _): name;
			case DClass(name, _, _): name;
			case DExtern(name, _): name;
			case DImport(path, _): path;
			case DExternCss(_): "Raw CSS";
		}
	}

	function createTypeHover(def:Definition):String
	{
		final name = getTypeName(def.kind);

		final type = switch (def.kind)
		{
			case DClass(_, parent, _):
				"Class" + (parent != null ? ' (extends $parent)' : "");
			case DRule(_, _):
				"Rule";
			case DStruct(_, _):
				"Struct";
			case DAbstract(_, _):
				"Abstract";
			case DExtern(_, _):
				"Extern Type";
			case DImport(_, isUrl):
				isUrl ? "Remote Import" : "Module Import";
			default:
				"Definition";
		}

		return '**$type**: `$name`\n';
	}

	function getFieldHover(def:Definition, offset:Int):Null<String>
	{
		final fields:Array<Field> = switch (def.kind)
		{
			case DRule(_, f), DStruct(_, f), DAbstract(_, f), DClass(_, _, f): f;
			default: [];
		}

		for (field in fields)
		{
			if (!offset.isWithin(field.pos))
				continue;

			final hover = switch (field.kind)
			{
				case FVar(nameLoc, typeNodeLoc, valueExpr, _):
					if (offset.isWithin(nameLoc.pos))
					{
						final typeName = getTypeName(def.kind);

						'**Property**: `${nameLoc.t}`\n\nDeclared in `${typeName}`';
					}
					else if (offset.isWithin(typeNodeLoc.pos))
					{
						final typeStr = sema.typeToString(typeNodeLoc.t);

						'**Type**: `$typeStr`';
					}
					else if (valueExpr != null && offset.isWithin(valueExpr))
					{
						final valueInfo = getExprInfo(valueExpr);

						'**Value Expression**\n\n$valueInfo';
					}
					else null;
				case FExternCss(contentLoc):
					if (offset.isWithin(contentLoc.pos))
					{
						'**Injected CSS**';
					}
					else null;
			}

			if (hover != null)
				return hover;
		}
		return null;
	}

	function getExprInfo(e:Expr):String
	{
		return switch (e.expr)
		{
			case EConst(CColor(c)): "Constant Color: `" + c + "`";
			case EConst(CInt(v, unit)): "Integer Value: `" + v + (unit != null ? unit : "") + "`";
			case EConst(CString(s)): "String literal";
			case EId(id): "Reference to: `" + id + "`";
			case EBinop(op, _, _): "Binary operation: `" + op + "`";
			default: "Expression";
		}
	}

	// Definition

	public function getDefinition(doc:DocumentData, offset:Int):Pos
	{
		final module = parseModule(doc);

		for (id => def in module)
		{
			switch (def.kind)
			{
				case DImport(path, false):
					if (def.namePos != null && offset.isWithin(def.namePos))
					{
						final module = getModulePath(path);

						if (module != null)
							return {
								file: module,
								min: 0,
								max: 0,
								line: 1,
								char: 0,
								endLine: 1,
								endChar: 0
							}
					}
				case DRule(_, fields), DStruct(_, fields), DAbstract(_, fields), DClass(_, _, fields):
					if (offset.isWithin(def.contentPos))
					{
						final loc:Pos = checkRuleContent(offset, fields);

						if (loc != null)
						{
							return loc;
						}
					}
				default:
			}
		}

		return null;
	}

	function checkRuleContent(offset:Int, fields:Array<Field>):Pos
	{
		for (field in fields)
		{
			if (offset.isWithin(field.pos))
				switch (field.kind)
				{
					case FVar(name, type, value, isDefault):
						if (offset.isWithin(type.pos))
						{
							final type = sema.typeImpls.get(sema.typeToString(type.t));

							if (type != null)
							{
								return type.namePos;
							}
						}
					case FExternCss(content):
				}
		}

		return null;
	}

	public function generateCss(doc:DocumentData):String
	{
		return new tcss.Generator().generate(analyze(doc).ast);
	}

	// Completions

	public function getCompletions(doc:DocumentData, offset:Int):Array<CompletionData>
	{
		parseModule(doc, offset);

		if (parser.suggestion == null)
			return null;

		var items:Array<CompletionData> = [];

		switch (parser.suggestion)
		{
			case SField:
				for (type in sema.typeImpls)
				{
					final typeName:Null<String> = getTypeName(type.kind);

					if (offset.isWithin(type.contentPos))
					{
						switch (getType(typeName))
						{
							case null:
							case TClass(c):
								for (fName in getFieldsForClass(c.parentName, true))
								{
									items.push(createCompletionItem(fName.field, FIELD, SField, fName.type));
								}
							default:
						}
					}
				}

				for (typeName in sema.types.keys())
				{
					if (!StringTools.startsWith(typeName, 'std.'))
						items.push(createCompletionItem(typeName, CLASS, SType));
				}

			case SType:
				for (typeName in sema.types.keys())
				{
					items.push(createCompletionItem(typeName, CLASS, SType));
				}

			case SFieldName(typeNode):
				final className = sema.typeToString(typeNode);
				for (f in getFieldsForClass(className))
				{
					items.push(createCompletionItem(f.field, FIELD, parser.suggestion, f.type));
				}

			case SExpr(typeNode):

				@:privateAccess final type = sema.followType(sema.getType(typeNode));

				switch (type)
				{
					case TStdType(TEnum(t, values)):
						for (v in values)
						{
							items.push(createCompletionItem(sema.tcssTypeToString(v), ENUMVALUE, parser.suggestion));
						}
					default:
				}
		}

		return items;
	}

	function getFieldsForClass(typeName:String, ?recursive:Bool = true):Array<{type:String, field:String}>
	{
		final type = getType(typeName);

		if (type == null)
			return [];

		var results:Array<{type:String, field:String}> = [];

		function collect(rule:TCssRule)
		{
			if (recursive)
				if (rule is TCssClass)
				{
					var parent = (cast rule : TCssClass).parent;
					if (parent != null)
						collect(parent);
				}

			for (f in rule.fields)
			{
				switch (f.kind)
				{
					case FVar(name, _, _, _):
						results.push({type: rule.name, field: name.t});
					default:
				}
			}
		}

		collect(Tools.getRule(type));

		return results;
	}

	function createCompletionItem(label:String, kind:CompletionKind, ?suggestion:Suggestion, ?contextClass:String):CompletionData
	{
		final item:CompletionData = {label: label, kind: kind}

		if (suggestion == null)
			return item;

		switch (suggestion)
		{
			case SField:
				final info = getFieldCompletion(contextClass, label);
				final val:String = info.defaultValue != "" ? '$${1:${info.defaultValue}}' : "$1";
				item.insertText = '${info.typeStr} $label = $val;';
				item.isSnippet = true;

				item.detail = 'Property of $contextClass';

			case SType:
				item.insertText = label;

				item.detail = "Type";

			case SFieldName(typeNode):
				final className:String = sema.typeToString(typeNode);
				final info = getFieldCompletion(className, label);

				var valuePart = info.defaultValue != "" ? '$${1:${info.defaultValue}}' : "$1";
				var snippet = '${info.typeStr} $label = $valuePart;';

				item.insertText = snippet;
				item.isSnippet = true;

				item.detail = 'Property of $className';
				item.documentation = 'Inserts full declaration: ${info.typeStr} $label';

			case SExpr(typeNode):
				item.insertText = label;
				item.detail = 'Value for ${sema.typeToString(typeNode)}';
		}

		return item;
	}

	function getFieldCompletion(className:String, fieldName:String):{typeStr:String, defaultValue:String}
	{
		final type = getType(className);
		if (type == null)
			return {typeStr: "dynamic", defaultValue: ""};

		var field = Tools.findFieldInRule(Tools.getRule(type), fieldName);

		if (field == null)
			return {typeStr: "dynamic", defaultValue: ""};

		switch (field.kind)
		{
			case FVar(_, typeNode, _, _):
				var typePath = sema.typeToString(typeNode.t);
				var tcssType = getType(typePath);

				if (tcssType != null)
				{
					var followed = @:privateAccess sema.followType(tcssType);

					switch (followed)
					{
						case TStdType(TEnum(t, values)) if (values.length > 0):
							var firstVal = switch (values[0])
							{
								case TStdType(TIdent(i)): i;
								default: "";
							};
							return {typeStr: typePath, defaultValue: firstVal};
						default:
					}
				}
				return {typeStr: typePath, defaultValue: ""};
			default:
				return {typeStr: "dynamic", defaultValue: ""};
		}
	}
}
#end
