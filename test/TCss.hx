import tcss.Generator;
import sys.FileSystem;
import tcss.Expr.Module;
import tcss.*;
import sys.io.File;

final dirs:Array<String> = ['test'];

function main()
{
	addStdDir();

	var ast = importModule('main', 30);

	final sema = new Sema();
	var typedAst = sema.analyze(ast, importModule.bind(_, null));

	trace(typedAst);

	trace(sema.typeImpls);

	trace(new Generator().generate(typedAst));
}

function importModule(rawPath:String, ?cursor:Int):Module
{
	var path = null;

	for (dir in dirs)
	{
		if (FileSystem.exists('$dir/$rawPath.tcss'))
			path = '$dir/$rawPath.tcss';
	}

	if (path == null)
		throw 'Can not find module: `$rawPath`';

	final content = File.getContent(path);

	var tokens = new tcss.Lexer(content).tokenize();

	var parser = new Parser();

	parser.enableRecovery = true;

	var ast = parser.parse(path, tokens, cursor);

	if (parser.suggestion != null)
		trace(parser.suggestion);

	return ast;
}

function addStdDir()
{
	try
	{
		var process = new sys.io.Process("haxelib", ["libpath", 'octa-tcss']);

		var path:String = StringTools.trim(process.stdout.readAll().toString());
		var error:String = process.stderr.readAll().toString();

		process.close();

		if (path != "")
		{
			dirs.push(path + 'std');
		}
		else
		{
			trace("Haxelib error: " + error);
		}
	} catch (e:Dynamic)
	{
		trace("Error: " + e);
	}
}
