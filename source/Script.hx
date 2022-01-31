import cpp.Reference;
import cpp.Lib;
import cpp.Pointer;
import cpp.RawPointer;
import cpp.Callable;
import llua.State;
import llua.Convert;
import ModSupport.ModScript;
import haxe.Constraints.Function;
import haxe.DynamicAccess;
import lime.app.Application;
using StringTools;

import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;
import EngineSettings.Settings;
import haxe.Exception;

// HSCRIPT
import hscript.Interp;

// LUA
import llua.Lua;
import llua.LuaL;

class Script {
    public var fileName:String = "";
    public function new() {

    }

    public static function fromPath(path:String):Script {
        var script = create(path);
        if (script != null) {
            script.loadFile(path);
            return script;
        } else {
            return null;
        }
    }

    public static function create(path:String):Script {
        var p = path.toLowerCase();
        var ext = Path.extension(p);
        trace('path : "$path"');
        trace('ext :');

        var scriptExts = ["lua", "hscript", "hx"];
        if (ext == "") {
            for (e in scriptExts) {
                if (FileSystem.exists('$p.$e')) {
                    p = '$p.$e';
                    ext = e;
                    break;
                }
            }
        }
        switch(ext.toLowerCase()) {
            case 'hx' | 'hscript':
                trace("HScript");
                return new HScript();
            case 'lua':
                trace("Lua");
                return new LuaScript();
        }
        trace('ext not found : $ext for $path');
        return null;
    }

    public function executeFunc(funcName:String, ?args:Array<Any>):Dynamic {
        throw new Exception("NOT IMPLEMENTED !");
        return null;
    }

    public function setVariable(name:String, val:Dynamic) {
        throw new Exception("NOT IMPLEMENTED !");
    }

    public function getVariable(name:String):Dynamic {
        throw new Exception("NOT IMPLEMENTED !");
        return null;
    }

    public function trace(text:String) {
        trace(text);
        if (Settings.engineSettings.data.developerMode) {
            for (t in text.split("\n")) PlayState.log.push(t);
        }
    }

    public function loadFile(path:String) {
        throw new Exception("NOT IMPLEMENTED !");
    }

    public function destroy() {

    }
}

class ScriptPack {
    public var scripts:Array<Script> = [];
    public var scriptModScripts:Array<ModScript> = [];
    public function new(scripts:Array<ModScript>) {
        for (s in scripts) {
            var sc = Script.create('${Paths.getModsFolder()}\\${s.path}');
            if (sc == null) continue;
            ModSupport.setScriptDefaultVars(sc, s.mod, {});
            this.scripts.push(sc);
            scriptModScripts.push(s);
        }
    }

    public function loadFiles() {
        for (k=>sc in scripts) {
            var s = scriptModScripts[k];
            sc.loadFile('${Paths.getModsFolder()}\\${s.path}');
        }
    }

    public function executeFunc(funcName:String, ?args:Array<Any>, ?defaultReturnVal:Any) {
        var a = args;
        if (a == null) a = [];
        for (script in scripts) {
            var returnVal = script.executeFunc(funcName, a);
            if (returnVal != defaultReturnVal && defaultReturnVal != null) {
                #if messTest trace("found"); #end
                return returnVal;
            }
        }
        return defaultReturnVal;
    }

    public function setVariable(name:String, val:Dynamic) {
        for (script in scripts) script.setVariable(name, val);
    }

    public function getVariable(name:String, defaultReturnVal:Any) {
        for (script in scripts) {
            var variable = script.getVariable(name);
            if (variable != defaultReturnVal) {
                return variable;
            }
        }
        return defaultReturnVal;
    }

    public function destroy() {
        for(script in scripts) script.destroy();
        scripts = null;
    }
}

class HScript extends Script {
    public var hscript:Interp;
    public function new() {
        hscript = new Interp();
        super();
    }

    public override function executeFunc(funcName:String, ?args:Array<Any>):Dynamic {
        if (hscript == null) {
            this.trace("hscript is null");
            return null;
        }
		if (hscript.variables.exists(funcName)) {
            var f = hscript.variables.get(funcName);
            if (args == null) {
                var result = null;
                try {
                    result = f();
                } catch(e) {
                    this.trace('$e');
                }
                Paths.copyBitmap = false;
                return result;
            } else {
                var result = null;
                try {
                    result = Reflect.callMethod(null, f, args);
                } catch(e) {
                    this.trace('$e');
                }
                Paths.copyBitmap = false;
                return result;
            }
			// f();
		}
        return null;
    }

    public override function loadFile(path:String) {
        if (path.trim() == "") return;
        fileName = Path.withoutDirectory(path);
        var p = path;
        if (Path.extension(p) == "") {
            var exts = ["hx", "hscript"];
            for (e in exts) {
                if (FileSystem.exists('$p.$e')) {
                    p = '$p.$e';
                    fileName += '.$e';
                    break;
                }
            }
        }
        try {
            hscript.execute(ModSupport.getExpressionFromPath(p, false));
        } catch(e) {
            this.trace('${e.message}');
        }
    }

    public override function trace(text:String) {
        var posInfo = hscript.posInfos();

        // var fileName = posInfo.fileName;
        var lineNumber = Std.string(posInfo.lineNumber);
        var methodName = posInfo.methodName;
        var className = posInfo.className;
        trace('$fileName:$methodName:$lineNumber: $text');

        if (!Settings.engineSettings.data.developerMode) return;
        for (e in ('$fileName:$methodName:$lineNumber: $text').split("\n")) PlayState.log.push(e.trim());
    }

    public override function setVariable(name:String, val:Dynamic) {
        hscript.variables.set(name, val);
    }

    public override function getVariable(name:String):Dynamic {
        return hscript.variables.get(name);
    }
}

typedef LuaObject = {
    var varPath:String;
    var set:(String,String)->Void;
    var get:(String)->LuaObject;
    // var toLua
}

class LuaScript extends Script {
    public var state:llua.State;
    public var variables:Map<String, Dynamic> = [];

    function getVar(v:String) {
        var splittedVar = v.split(".");
        if (splittedVar.length == 0) return null;
        var currentObj = variables[splittedVar[0]];
        for (i in 1...splittedVar.length) {
            var property = Reflect.getProperty(currentObj, splittedVar[i]);
            if (property != null) {
                currentObj = property;
            } else {
                this.trace('Variable $v doesn\'t exist or is equal to null.');
                return null;
            }
        }
        return currentObj;
    }
    public function new() {
        super();
        state = LuaL.newstate();
        Lua.init_callbacks(state);
        LuaL.openlibs(state);
        Lua_helper.register_hxtrace(state);
        
        Lua_helper.add_callback(state, "set", function(v:String, value:Dynamic) {
            var splittedVar = v.split(".");
            if (splittedVar.length == 0) return false;
            if (splittedVar.length == 1) {
                variables[v] = value;
                return true;
            }
            var currentObj = variables[splittedVar[0]];
            for (i in 1...splittedVar.length - 1) {
                var property = Reflect.getProperty(currentObj, splittedVar[i]);
                if (property != null) {
                    currentObj = property;
                } else {
                    this.trace('Variable $v doesn\'t exist or is equal to null.');
                    return false;
                }
            }
            // var property = Reflect.getProperty(currentObj, splittedVar[splittedVar.length - 1]);
            // if (property != null) {
            var finalVal = value;
            if (Std.is(finalVal, String)) {
                var str = cast(finalVal, String);
                if (str.startsWith("$")) {
                    var v = getVar(str.substr(1));
                    if (v != null) {
                        finalVal = v;
                    }
                }
            }
            try {
                Reflect.setProperty(currentObj, splittedVar[splittedVar.length - 1], finalVal);
                return true;
            } catch(e) {
                this.trace('Variable $v doesn\'t exist.');
                return false;
            }
        });
        Lua_helper.add_callback(state, "get", function(v:String, ?globalName:String) {
            var r = getVar(v);
            if (globalName != null) {
                variables[v] = r;
                return true;
            } else {
                return r;
            }
        });
        Lua_helper.add_callback(state, "call", function(v:String, ?resultName:String, ?args:Array<Dynamic>):Dynamic {
            if (args == null) args = [];
            var splittedVar = v.split(".");
            if (splittedVar.length == 0) return false;
            var currentObj = variables[splittedVar[0]];
            for (i in 1...splittedVar.length - 1) {
                var property = Reflect.getProperty(currentObj, splittedVar[i]);
                if (property != null) {
                    currentObj = property;
                } else {
                    this.trace('Variable $v doesn\'t exist or is equal to null.');
                    return false;
                }
            }
            var func = Reflect.getProperty(currentObj, splittedVar[splittedVar.length - 1]);

            var finalArgs = [];
            for (a in args) {
                if (Std.is(a, String)) {
                    var str = cast(a, String);
                    if (str.startsWith("$")) {
                        var v = getVar(str.substr(1));
                        if (v != null) {
                            finalArgs.push(v);
                        } else {
                            finalArgs.push(a);
                        }
                    } else {
                        finalArgs.push(a);
                    }
                } else {
                    finalArgs.push(a);
                }
            }
            if (func != null) {
                var result = null;
                try {
                    result = Reflect.callMethod(null, func, finalArgs);
                } catch(e) {
                    this.trace('$e');
                }
                Paths.copyBitmap = false;
                if (resultName == null) {
                    return result;
                } else {
                    variables[resultName] = result;
                    return '$' + resultName;
                }
            } else {
                this.trace('Function $v doesn\'t exist or is equal to null.');
                return false;
            }
        });
        Lua_helper.add_callback(state, "createClass", function(name:String, className:String, params:Array<Dynamic>) {
            var cl = Type.resolveClass(className);
            if (cl == null) {
                if (variables[className] != null) {
                    if (Type.typeof(variables[className]) == Type.typeof(Class)) {
                        cl = cast(variables[className], Class<Dynamic>);
                    }
                }
            }
            variables[name] = Type.createInstance(cl, params);
        });
        Lua_helper.add_callback(state, "print", function(toPtr:Dynamic) {
            this.trace(Std.string(toPtr));
        });
        // Lua_helper.add_callback(state, "trace", function(text:String) {
        //     trace(text);
        // });
    }

    public override function loadFile(path:String) {
        // LuaL.loadfile(state, path);
        // LuaL.dostring(state, Paths.getTextOutsideAssets(path));
        var p = path;
        if (Path.extension(p) == "") {
            p = p + ".lua";
        }
        if (FileSystem.exists(p)) {
            if (LuaL.dostring(state, File.getContent(p)) != 0) {
                var err = Lua.tostring(state, -1);
                this.trace('$fileName: $err');
            }
        } else {
            this.trace("Lua script does not exist.");
        }
        fileName = Path.withoutDirectory(p);
    }

    public override function trace(text:String)
    {
        // LuaL.error(state, "%s");
        for(t in text.split("\n")) PlayState.log.push(t);
        trace(text);
    }

    public override function getVariable(name:String) {
        // Lua.getglobal()
        return variables[name];
    }

    // public override function executeFunc(name:String) {
    //     // Lua.getglobal()
    //     return variables[name];
    // }

    public override function setVariable(name:String, v:Dynamic) {
        // Lua.getglobal()
        variables[name] = v;
    }

    public override function executeFunc(funcName:String, ?args:Array<Any>) {
        // Gets func
        // Lua.
        
        if (args == null) args = [];
        Lua.getglobal(state, funcName);
        
        for (a in args) {
            Convert.toLua(state, a);
        }
        if (Lua.pcall(state, args.length, 1, 0) != 0) {
            var err = Lua.tostring(state, -1);
            if (err != "attempt to call a nil value") {
                this.trace('$fileName:$funcName():$err');
            }
        }
        return Convert.fromLua(state, Lua.gettop(state));
    }
}