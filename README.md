## Octacube Typed Cascading Style Sheets

**Octacube Typed Cascading Style Sheets (TCSS)** is a typed preprocessor that brings strict typing to CSS without compromising performance.

## Language Syntax Reference

TCSS supports modular imports, external rule definitions, abstract interfaces, and inline CSS blocks.

### Modules and Imports

Use `import` to bring in standard libraries or external resources.

```tcss
import std;

import @<url>;
```

### External Rules and Virtual Variables

Use `extern rule` to define global scope styles. Variables marked as `virtual` are compiled into CSS variables (custom properties).

```tcss
extern rule body {
    virtual color shadow = #000000; // Compiles to --shadow
    display.mode display = none;
}

```

### Classes

You can define structured styles using classes, which compile into standard CSS class selectors.

```tcss
class button
{
    size width = 12;
}

```

### Interfaces and Abstraction

Define reusable structures using `abstract` interfaces. Use `default` to set fallback values.

```tcss
abstract IButton {
    abstract size width;
    size height = 20px;
    color color = default #00ff00;
}

```

### Inline CSS Blocks

Use the `extern css </>` block to write standard CSS directly, with syntax highlighting support.

```tcss
extern css </>
.logo {
    display: none;
}
</>

```

### Inheritance and Collections

Classes can extend interfaces or other classes. You can also define `collection` classes for grouping multiple selectors.

```tcss
class button extends IButton
{
    size width = 123;
    extern css </>
    display: flex;
    </>
}

collection class A, B extends AB {
    size width = 123;
}

collection class(A:AC, B:BC) {}
```

## Install
`haxelib git octa-tcss https://github.com/Kriptel/Octa-tcss.git dev`

## Run
You can compile your TCSS files using the Haxe library runner. 

Execute the following command in your terminal:
```
haxelib run octa-tcss [options]
```

Available Options:
| Option                  | Description                                            |
| ----------------------- | ------------------------------------------------------ |
| `-i`, `--input <file>`  | Set input file                                         |
| `-o`, `--output <file>` | Set output file                                        |
| `-d`, `--dir <path>`    | Append directory to the list of search paths           |
| `-f`, `--force`         | Overwrite output files without asking for confirmation |
| `--suggestion`          | Enable suggestions                                     |
| `--enableRecovery`      | Try to recover from CSS errors                         |