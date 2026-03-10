package tcss;

import tcss.Expr;

enum TokenDef
{
	TId(id:String);
	TString(s:String);
	TUrl(path:String);
	TInt(i:Int);
	TFloat(f:Float);
	TColor(color:String);
	TOp(op:String);
	TRaw(raw:String); // </>abc</>
	TDot;
	TComma;
	TSemicolon;
	TBOpen;
	TBClose;
	TBrOpen;
	TBrClose;
	TDoubleDot;
	TLt; // <
	TMt; // >
	TEof;
}

@:forward
abstract Token(__Token) from __Token
{
	public var pos(get, never):Pos;

	inline function get_pos():Pos
	{
		return {
			min: this.s,
			max: this.e,
			line: this.l,
			file: this.f
		}
	}
}

private typedef __Token =
{
	var t:TokenDef;
	var s:Int;
	var e:Int;
	var l:Int;
	var f:String;
}

class Lexer
{
	var input:String;
	var file:String;
	var pos:Int = 0;
	var curLine:Int = 1;

	public function new(input:String, ?fileName:String = null)
	{
		this.input = input;
		this.file = fileName;
	}

	var char:Int = -1;

	function readChar():Int
	{
		var c:Int = -1;
		if (this.char != -1)
		{
			c = this.char;
			this.char = -1;
		}
		else
		{
			c = StringTools.fastCodeAt(input, pos++);
		}

		if (StringTools.isEof(c))
			return -1;

		if (c == '\n'.code)
		{
			curLine++;
		}

		return c;
	}

	var tokens:Array<Token> = [];

	public function tokenize():Array<Token>
	{
		while (true)
		{
			final start:Int = pos;

			final char:Int = readChar();

			if (char == -1)
				break;

			switch (char)
			{
				case ' '.code | '\t'.code | '\r'.code, '\n'.code:
				case '='.code | '|'.code, '%'.code:
					addToken(TOp(String.fromCharCode(char)), start);
				case '.'.code:
					addToken(TDot, start);
				case ';'.code:
					addToken(TSemicolon, start);
				case ':'.code:
					addToken(TDoubleDot, start);
				case ','.code:
					addToken(TComma, start);
				case '('.code:
					addToken(TBOpen, start);
				case ')'.code:
					addToken(TBClose, start);
				case '{'.code:
					addToken(TBrOpen, start);
				case '}'.code:
					addToken(TBrClose, start);
				case '<'.code:
					final char = readChar();

					if (char == '/'.code)
					{
						ensureChar('>'.code);
						addToken(TRaw(readRaw()), start);
					}
					else
					{
						this.char = char;
						addToken(TLt, start);
					}

				case '>'.code:
					addToken(TMt, start);
				case '/'.code:
					var char = readChar();

					if (char == '/'.code)
					{
						skipLineComment();
					}
					else if (char == '*'.code)
					{
						skipBlockComment();
					}
					else
					{
						this.char = char;
						addToken(TOp("/"), start, pos - 1);
					}
				case '@'.code:
					final char = readChar();

					if (char == '<'.code)
					{
						addToken(TUrl(readUntil(">".code)), start);
					}
					else
					{
						error(EUnexpectedChar(char));
					}
				case '"'.code:
					addToken(TString(readUntil('"'.code)), start);
				case '#'.code:
					addToken(TColor(readHex()), start);

				default:
					if (isDigit(char))
					{
						final i:Int = readInt(char);

						final char:Int = readChar();

						if (char == '.'.code)
						{
							final char:Int = readChar();

							if (!isDigit(char))
								error(EUnexpectedChar(char));

							final i2:String = readDigits(char);

							addToken(TFloat(Std.parseFloat(i + '.' + i2)), start);
						}
						else
						{
							this.char = char;
							addToken(TInt(i), start);
						}
					}
					else if (isIdentChar(char))
					{
						addToken(TId(readIdent(char)), start);
					}
					else
					{
						error(EUnexpectedChar(char));
					}
			}
		}
		addToken(TEof);
		return tokens;
	}

	function addToken(token:TokenDef, ?start:Int, ?end:Int, ?line:Int):Void
	{
		tokens.push(
			{
				t: token,
				s: start ?? pos,
				e: end ?? (char != -1 ? pos - 1 : pos),
				l: line ?? curLine,
				f: file
			});
	}

	function readIdent(firstChar:Int):String
	{
		var s:String = String.fromCharCode(firstChar);

		while (true)
		{
			final c:Int = readChar();
			if (isIdentChar(c) || isDigit(c))
			{
				s += String.fromCharCode(c);
			}
			else if (c == '\\'.code)
			{
				final c:Int = readChar();

				if (c != -1)
					s += '\\' + String.fromCharCode(c);
				else
					break;
			}
			else
			{
				this.char = c;
				break;
			}
		}

		return s;
	}

	function readRaw():String
	{
		var s:String = '';

		while (true)
		{
			final char:Int = readChar();

			switch (char)
			{
				case -1:
					break;
				case '<'.code:
					final char:Int = readChar();
					switch (char)
					{
						case -1:
							break;
						case '/'.code:
							var char = readChar();

							switch (char)
							{
								case -1:
									break;
								case '>'.code:
									return s;
									break;
								default:
									s += '/';
									this.char = char;
							}
						default:
							this.char = char;
					}
				default:
					s += String.fromCharCode(char);
			}
		}
		return s;
	}

	inline function readInt(firstChar:Int):Int
	{
		return Std.parseInt(readDigits(firstChar));
	}

	function readDigits(firstChar:Int):String
	{
		var s:String = String.fromCharCode(firstChar);

		while (true)
		{
			var char = readChar();

			if (char != -1 && isDigit(char))
			{
				s += String.fromCharCode(char);
			}
			else
			{
				this.char = char;
				break;
			}
		}

		return s;
	}

	function readHex():String
	{
		var s:String = '';
		while (true)
		{
			var c = readChar();
			if (c == -1)
				break;
			if (isHex(c))
			{
				s += String.fromCharCode(c);
			}
			else
			{
				this.char = c;
				break;
			}
		}
		return s;
	}

	function readUntil(endCharCode:Int):String
	{
		var s:String = '';
		while (true)
		{
			final char:Int = readChar();
			if (char == -1 || char == endCharCode)
				break;

			s += String.fromCharCode(char);
		}
		return s;
	}

	function skipLineComment():Void
	{
		while (true)
		{
			var char:Int = readChar();

			if (char == -1 || char == '\n'.code)
				break;
		}
	}

	function skipBlockComment():Void
	{
		while (true)
		{
			final char:Int = readChar();
			switch (char)
			{
				case -1:
					break;
				case '*'.code:
					final char = readChar();
					if (char == '/'.code)
						break;
					this.char = char;
			}
		}
	}

	function ensureChar(char:Int):Void
	{
		final c:Int = readChar();
		if (c != char)
		{
			error(EUnexpectedChar(c));
		}
	}

	inline function isIdentChar(c:Int):Bool
	{
		return (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || c == '_'.code || c == '.'.code || c == '-'.code;
	}

	inline function isDigit(c:Int):Bool
	{
		return c >= '0'.code && c <= '9'.code;
	}

	inline function isHex(c:Int):Bool
	{
		return isDigit(c) || (c >= 'a'.code && c <= 'f'.code) || (c >= 'A'.code && c <= 'F'.code);
	}

	function error(e:Error):Void
	{
		throw e;
	}
}
