package tcss;

import tcss.Type;
import tcss.Expr;

class Generator
{
	public function new() {}

	public function generate(ast:TypedAST):String
	{
		var buf = new StringBuf();

		for (node in ast)
		{
			switch (node)
			{
				case TRuleNode(selectors, body):
					buf.add(selectors.join(", "));
					buf.add(" {\n");
					for (content in body)
					{
						renderRuleContent(content, buf);
					}
					buf.add("}\n\n");

				case TAtRuleNode(name, params, block):
					buf.add('@' + name + ' ' + params);
					if (block != null)
					{
						buf.add(" {\n");
						buf.add(generate(block));
						buf.add("}\n");
					}
					else
					{
						buf.add(";\n");
					}

				case TRawCssNode(css):
					buf.add(css);
					buf.add("\n");
			}
		}

		return buf.toString();
	}

	private function renderRuleContent(content:RuleContent, buf:StringBuf):Void
	{
		switch (content)
		{
			case Field(field, type, value, important):
				buf.add('\t${validateFieldName(field)}: $value');
				if (important)
					buf.add(" !important");
				buf.add(";\n");

			case Variable(name, value):
				buf.add('\t--$name: $value;\n');

			case Raw(content):
				buf.add('\t$content\n');
		}
	}

	private function validateFieldName(field:String)
	{
		return StringTools.replace(field, '.', '-');
	}
}
