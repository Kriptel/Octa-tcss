package tcss;

import haxe.io.Path;
import tcss.Expr.Module;
import sys.FileSystem;
import sys.io.File;

class Run
{
	public static function main()
	{
		final libDir:String = Sys.getCwd();

		if (libDir == null)
		{
			Sys.exit(-1);
		}

		final libData = haxe.Json.parse(File.getContent(libDir + '/haxelib.json'));

		Sys.println('Octa Typed Cascading Style Sheets ' + libData.version);

		final args = Sys.args();

		final cwd:String = args.pop();

		var dirs:Array<String> = [cwd, libDir + 'std/'];
		var input:String = null;
		var output:String = null;
		var allowOverwrite:Bool = false;
		var suggestion:Bool = false;
		var enableRecovery:Bool = false;

		if (args.length == 0)
		{
			printHelp();
			return;
		}
		else
			while (args.length > 0)
			{
				switch (args.shift())
				{
					case "-d" | "--dir":
						final dir:String = args.shift();
						if (dir != null)
							dirs.push(dir);
					case "-i" | "--input":
						input = args.shift();
					case "-o" | "--output":
						output = args.shift();
					case "-f" | "--force":
						allowOverwrite = true;
					case "--suggestion":
						suggestion = true;
					case "--enableRecovery":
						enableRecovery = true;
					case "-h" | "--help":
						printHelp();
						return;
					case arg:
						Sys.println("Unknown argument: " + arg);
				}
			}

		if (input == null)
		{
			printHelp();
			return;
		}

		if (output == null)
		{
			output = Path.withoutExtension(input) + '.css';
		}

		start(cwd, dirs, input, output, allowOverwrite, suggestion, enableRecovery);
	}

	static function printHelp()
	{
		Sys.println("  Usage: haxelib run octa-tcss [options]");
		Sys.println("    -i, --input <file>     : Set input file");
		Sys.println("    -o, --output <file>    : Set output file");
		Sys.println("    -d, --dir <path>       : Append directory to the list of search paths");
		Sys.println("    -f, --force            : Overwrite output files without asking for confirmation");
		Sys.println("    --suggestion           : Enable suggestions");
		Sys.println("    --enableRecovery       : Try to recover from CSS errors");
	}

	static function start(cwd:String, dirs:Array<String>, input:String, output:String, allowOverwrite:Bool, suggestion:Bool, enableRecovery:Bool)
	{
		function importModule(rawPath:String):Module
		{
			var path = null;

			for (dir in dirs)
			{
				if (FileSystem.exists('$dir/$rawPath.tcss'))
					path = '$dir/$rawPath.tcss';
			}

			if (path == null)
				throw 'Can not find module: `$rawPath`';

			final tokens = new tcss.Lexer(File.getContent(path)).tokenize();
			final parser = new Parser();

			parser.enableRecovery = enableRecovery;

			var ast = parser.parse(path, tokens);

			if (enableRecovery)
			{
				for (error in parser.errors)
					Sys.println('[Error (ignored)]: ' + error);
			}

			if (suggestion && parser.suggestion != null)
			{
				Sys.println('[Suggestion]: ' + parser.suggestion);
			}

			return ast;
		}

		final sema = new Sema();
		sema.enableRecovery = enableRecovery;
		final typedAst = sema.analyze(importModule('main'), importModule);

		if (enableRecovery)
		{
			for (error in sema.errors)
				Sys.println('[Error (ignored)]: ' + error);
		}

		final content = new Generator().generate(typedAst);

		final outputPath = cwd + '/' + output;

		if (FileSystem.exists(outputPath))
		{
			if (!allowOverwrite)
			{
				Sys.print('File "$outputPath" already exists. Overwrite? (y/N): ');

				final input = Sys.stdin().readLine().toLowerCase();

				if (input != "y" && input != "yes")
				{
					Sys.println("Operation cancelled.");
					Sys.exit(0);
				}
			}
		}

		File.saveContent(outputPath, content);
	}
}
