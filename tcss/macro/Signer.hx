package tcss.macro;

import haxe.macro.Context;
import sys.io.Process;
import sys.FileSystem;
import sys.io.File;

class Signer
{
	inline public static final privateKey:String = "certs/private.pem";

	public static function signOutput(filePath:String)
	{
		Context.onAfterGenerate(() ->
		{
			final signatureFilePath:String = filePath + ".sig";

			if (!FileSystem.exists(privateKey))
			{
				Sys.println("Error: Private key not found in" + privateKey);
				return;
			}

			if (!FileSystem.exists(filePath))
			{
				Sys.println("Error: Could not find file '" + filePath + "'");
				return;
			}

			final args:Array<String> = ["dgst", "-sha256", "-sign", privateKey, "-out", signatureFilePath, filePath];

			final process = new Process("openssl", args);

			if (process.exitCode() == 0)
			{
				Sys.println("Signature created:" + signatureFilePath);
			}
			else
			{
				Sys.println("OpenSSL error: " + process.stderr.readAll().toString());
			}
			process.close();
		});
	}
}
