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
			char: this.c,
			endLine: this.el,
			endChar: this.ec,
			file: this.f
		}
	}
}

private typedef __Token =
{
	var t:TokenDef;

	var s:Int; // min
	var e:Int; // max

	var l:Int; // line
	var c:Int; // char
	var el:Int; // line
	var ec:Int; // char

	var f:String;
}

class Lexer
{
	var input:String;
	var file:String;
	var pos:Int = 0;
	var curLine:Int = 1;
	var curCharNum:Int = 0;

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
			curCharNum++;
		}

		if (StringTools.isEof(c))
			return -1;

		if (c == '\n'.code)
		{
			curLine++;
			curCharNum = 0;
		}

		return c;
	}

	var tokens:Array<Token> = [];

	public function tokenize():Array<Token>
	{
		while (true)
		{
			final start:Int = pos;
			final startLine:Int = curLine;
			final startChar:Int = curCharNum;

			final char:Int = readChar();

			if (char == -1)
				break;

			switch (char)
			{
				case ' '.code | '\t'.code | '\r'.code, '\n'.code:
				case '='.code | '|'.code, '%'.code:
					addToken(TOp(String.fromCharCode(char)), start, null, startLine, startChar);
				case '.'.code:
					addToken(TDot, start, null, startLine, startChar);
				case ';'.code:
					addToken(TSemicolon, start, null, startLine, startChar);
				case ':'.code:
					addToken(TDoubleDot, start, null, startLine, startChar);
				case ','.code:
					addToken(TComma, start, null, startLine, startChar);
				case '('.code:
					addToken(TBOpen, start, null, startLine, startChar);
				case ')'.code:
					addToken(TBClose, start, null, startLine, startChar);
				case '{'.code:
					addToken(TBrOpen, start, null, startLine, startChar);
				case '}'.code:
					addToken(TBrClose, start, null, startLine, startChar);
				case '<'.code:
					final char = readChar();

					if (char == '/'.code)
					{
						ensureChar('>'.code);
						addToken(TRaw(readRaw()), start, null, startLine, startChar);
					}
					else
					{
						this.char = char;
						addToken(TLt, start, null, startLine, startChar);
					}

				case '>'.code:
					addToken(TMt, start, null, startLine, startChar);
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
						addToken(TOp("/"), start, pos - 1, startLine, startChar);
					}
				case '@'.code:
					final char = readChar();

					if (char == '<'.code)
					{
						addToken(TUrl(readUntil(">".code)), start, null, startLine, startChar);
					}
					else
					{
						error(EUnexpectedChar(char));
					}
				case '"'.code:
					addToken(TString(readUntil('"'.code)), start, null, startLine, startChar);
				case '#'.code:
					addToken(TColor(readHex()), start, null, startLine, startChar);

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

							addToken(TFloat(Std.parseFloat(i + '.' + i2)), start, null, startLine, startChar);
						}
						else
						{
							this.char = char;
							addToken(TInt(i), start, null, startLine, startChar);
						}
					}
					else if (isIdentChar(char))
					{
						addToken(TId(readIdent(char)), start, null, startLine, startChar);
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

	function addToken(token:TokenDef, ?start:Int, ?end:Int, ?line:Int, ?char:Int, ?endLine:Int, ?endChar:Int):Void
	{
		tokens.push(
			{
				t: token,
				s: start ?? pos,
				e: end ?? (char != -1 ? pos - 1 : pos),
				l: line ?? curLine,
				c: char ?? curCharNum,
				el: endLine ?? curLine,
				ec: endChar ?? curCharNum - 1,
				f: file
			});
	}

	function readIdent(firstChar:Int):String
	{
		final s:StringBuf = new StringBuf();
		s.addChar(firstChar);

		while (true)
		{
			final c:Int = readChar();
			if (isIdentChar(c) || isDigit(c))
			{
				s.addChar(c);
			}
			else if (c == '\\'.code)
			{
				final c:Int = readChar();

				if (c != -1)
					s.addChar(c);
				else
					break;
			}
			else
			{
				this.char = c;
				break;
			}
		}

		return s.toString();
	}

	function readRaw():String
	{
		final s:StringBuf = new StringBuf();

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
									return s.toString();
								default:
									s.add('/');
									this.char = char;
							}
						default:
							this.char = char;
					}
				default:
					s.addChar(char);
			}
		}

		return s.toString();
	}

	inline function readInt(firstChar:Int):Int
	{
		return Std.parseInt(readDigits(firstChar));
	}

	function readDigits(firstChar:Int):String
	{
		final s:StringBuf = new StringBuf();
		s.addChar(firstChar);

		while (true)
		{
			final char:Int = readChar();

			if (char != -1 && isDigit(char))
			{
				s.addChar(char);
			}
			else
			{
				this.char = char;
				break;
			}
		}

		return s.toString();
	}

	function readHex():String
	{
		final s:StringBuf = new StringBuf();

		while (true)
		{
			final c:Int = readChar();
			if (c == -1)
				break;
			if (isHex(c))
			{
				s.addChar(c);
			}
			else
			{
				this.char = c;
				break;
			}
		}

		return s.toString();
	}

	function readUntil(endCharCode:Int):String
	{
		final s:StringBuf = new StringBuf();
		while (true)
		{
			final char:Int = readChar();
			if (char == -1 || char == endCharCode)
				break;

			s.addChar(char);
		}

		return s.toString();
	}

	function skipLineComment():Void
	{
		while (true)
		{
			final char:Int = readChar();

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
		return (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || c == '.'.code || c == '_'.code || c == '-'.code;
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
