define(["js/ffi-helpers", "trove/srcloc", "trove/error", "trove/contracts", "compiler/compile-structs.arr", "trove/image-lib", "./output-ui.js", "/js/share.js"], function(ffiLib, srclocLib, errorLib, contractsLib, csLib, imageLib, outputUI) {

  var shareAPI = makeShareAPI("");
  function drawError(container, editors, runtime, exception) {
    var ffi = ffiLib(runtime, runtime.namespace);
    var image = imageLib(runtime, runtime.namespace);
    var cases = ffi.cases;
    runtime.loadModules(runtime.namespace, [srclocLib, errorLib, csLib, contractsLib], function(srcloc, error, cs, contracts) {
      var get = runtime.getField;

      function mkPred(pyretFunName) {
        return function(val) { return get(error, pyretFunName).app(val); }
      }

      var isContractError = get(contracts, "ContractResult").app;

      /*
      var isRuntimeError = mkPred("RuntimeError");

      function setImmediate(f) { setTimeout(f, 0); }
      function renderValueIn(val, container) {
        setImmediate(function() {
          outputUI.renderPyretValue(container, runtime, val);
        });
      }*/

      function pyretizeSpyretLoc(spyretLoc) {
        return runtime.makeSrcloc([spyretLoc.source,
          spyretLoc.startRow, spyretLoc.startCol, spyretLoc.startChar,
          spyretLoc.endRow, spyretLoc.endCol, spyretLoc.endChar
        ])
      }

      // Exception will be one of:
      // - an Array of compileErrors (this is legacy, but useful for old versions),
      // - a PyretException with a list of compileErrors
      // - a PyretException with a stack and a Pyret value error
      // - something internal and JavaScripty, which we don't want
      //   users to see but will have a hard time ruling out
      if(exception instanceof Array) {
        drawCompileErrors(exception);
      }
      if(exception.exn instanceof Array) {
        drawCompileErrors(exception.exn);
      } else if(runtime.isPyretException(exception)) {
        drawPyretException(exception);
      } else if (typeof(exception) === 'string') {

        var spyretExn = JSON.parse(exception);
        if (spyretExn.type === 'spyret-parse-error') {
          var pyretLoc = pyretizeSpyretLoc(spyretExn.loc)
          var spyretErrType = spyretExn.type
          var spyretOrigMsg = spyretExn.msg
          var spyretErrPkt = spyretExn.errPkt
          var spyretErrMsg = spyretOrigMsg
          var spyretErrArgLocs = []
          if (spyretErrPkt) {
            spyretErrMsg = spyretErrPkt.errMsg || spyretOrigMsg
            spyretErrArgLocs = spyretErrPkt.errArgLocs || []
          }
          var spyretErrArgs = []
          var spyretErrLocs = []
          var it
          for (var i = 0; i < spyretErrArgLocs.length; i++) {
            it = spyretErrArgLocs[i]
            spyretErrArgs.push(it[0])
            spyretErrLocs.push(pyretizeSpyretLoc(it[1]))
            /*
            if (it.length > 2) {
              for (i = 2; i < it.length; i++) {
                spyretErrArgs.push('❧')
                spyretErrLocs.push(pyretizeSpyretLoc(it[i]))
              }
            }
            */
          }
          // make a PyretFailException and call drawPyretException on it
          var spyretErrArgsList = runtime.ffi.makeList(spyretErrArgs)
          var spyretErrLocsList = runtime.ffi.makeList(spyretErrLocs)
          var spyretParseExn = get(error, spyretErrType).app(pyretLoc, spyretErrMsg, spyretErrArgsList, spyretErrLocsList)
          var pyretExn = runtime.makePyretFailException(spyretParseExn)
          drawPyretException(pyretExn)

        } else {
          drawUnknownException(spyretExn)
        }

      } else {
        drawUnknownException(exception);
      }

      function singleHover(dom, loc) {
        if (loc === undefined) {
          console.error("Given an undefined location to highlight, at", (new Error()).stack);
          return;
        }
        outputUI.hoverLink(editors, runtime, srcloc, dom, loc, "error-highlight");
      }

      function drawSpyretParseError(msg, loc) {
        var dom = $("<div>").addClass("parse-error");
        var srcElem = outputUI.drawSrcloc(editors, runtime, loc);
        dom.append($("<p>").text(msg));
        singleHover(srcElem, loc);
        container.append(dom);
      }

      function drawCompileErrors(e) {
        console.log(outputUI.makePalette);
        var mkPalette = outputUI.makePalette(runtime);
        function drawCompileError(e) {
          runtime.runThunk(
            function() {
              return get(e, "render-fancy-reason").app(mkPalette); },
            function(errorDisp) {
              if (runtime.isSuccessResult(errorDisp)) {
                var dom = outputUI.renderErrorDisplay(editors, runtime, errorDisp.result, e.pyretStack || []);
                dom.addClass("compile-error");
                container.append(dom);
              } else {
                container.append($("<span>").addClass("compile-error")
                                 .text("An error occurred rendering the reason for this error; details logged to the console"));
                console.log(errorDisp.exn);
              }
            });
        }
        e.forEach(drawCompileError);
      }

      function drawExpandableStackTrace(e) {
        var srclocStack = e.pyretStack.map(runtime.makeSrcloc);
        var isSrcloc = function(s) { return runtime.unwrap(get(srcloc, "is-srcloc").app(s)); }
        var userLocs = srclocStack.filter(function(l) { return l && isSrcloc(l); });
        var container = $("<div>");
        if(userLocs.length > 0) {
          container.append($("<p>").text("Evaluation in progress when the error occurred:"));
          userLocs.forEach(function(ul) {
            var slContainer = $("<div>");
            var srcloc = outputUI.drawSrcloc(editors, runtime, ul);
            slContainer.append(srcloc);
            singleHover(srcloc, ul);
            container.append(slContainer);
          });
          return outputUI.expandableMore(container);
        } else {
          return container;
        }
      }

      function drawPyretException(e) {
        function drawRuntimeErrorToString(e) {
          return function() {
            var dom = $("<div>");
            var exnstringContainer = $("<div>");
            dom
              .addClass("compile-error")
              .append($("<p>").text("Error: "))
              .append(exnstringContainer)
              .append($("<p>"))
              .append(drawExpandableStackTrace(e));
            container.append(dom);
            if(runtime.isPyretVal(e.exn)) {
              outputUI.renderPyretValue(exnstringContainer, runtime, e.exn);
            }
            else {
              exnstringContainer.text(String(e.exn));
            }
          }
        }

        function drawPyretRuntimeError() {
          var locToAST = outputUI.locToAST(runtime, editors, srcloc);
          var locToSrc = outputUI.locToSrc(runtime, editors, srcloc);
          var mkPalette = outputUI.makePalette(runtime);
          runtime.runThunk(
            function() { return get(e.exn, "render-fancy-reason").app(locToAST, locToSrc, mkPalette); },
            function(errorDisp) {
              if (runtime.isSuccessResult(errorDisp)) {
                var dom = outputUI.renderErrorDisplay(editors, runtime, errorDisp.result, e.pyretStack);
                dom.addClass("compile-error");
                container.append(dom);
                dom.append(drawExpandableStackTrace(e));
              } else {
                  console.log(errorDisp.exn);
              }
            });
        }

        function drawPyretContractFailure(err) {
          var locToAST = outputUI.locToAST(runtime, editors, srcloc);
          var locToSrc = outputUI.locToSrc(runtime, editors, srcloc);
          var mkPalette = outputUI.makePalette(runtime);
          var isArg = ffi.isFailArg(err);
          var loc = get(err, "loc");
          var reason = get(err, "reason");
          runtime.runThunk(
            function() { return get(err, "render-fancy-reason").app(locToAST, locToSrc, mkPalette); },
            function(errorDisp) {
              if (runtime.isSuccessResult(errorDisp)) {
                var dom = outputUI.renderErrorDisplay(editors, runtime, errorDisp.result, e.pyretStack);
                dom.addClass("parse-error");
                container.append(dom);
                dom.append(drawExpandableStackTrace(e));
              } else {
                container.append($("<span>").addClass("compile-error")
                                 .text("An error occurred rendering the reason for this error; details logged to the console"));
                console.log(errorDisp.exn);
              }
            });
        }

        function drawPyretParseError() {
          var locToSrc = outputUI.locToSrc(runtime, editors, srcloc);
          var mkPalette = outputUI.makePalette(runtime);
          runtime.runThunk(
            function() { return get(e.exn, "render-fancy-reason").app(locToSrc, mkPalette); },
            function(errorDisp) {
              if (runtime.isSuccessResult(errorDisp)) {
                var dom = outputUI.renderErrorDisplay(editors, runtime, errorDisp.result, e.pyretStack || []);
                dom.addClass("parse-error");
                container.append(dom);
              } else {
                container.append($("<span>").addClass("compile-error")
                                 .text("An error occurred rendering the reason for this error; details logged to the console"));
                console.log(errorDisp.exn);
              }
            });
        }
        if(!runtime.isObject(e.exn)) {
          drawRuntimeErrorToString(e)();
        }
        else if(isContractError(e.exn)) {
          drawPyretContractFailure(e.exn);
        }
        else if(mkPred("RuntimeError")(e.exn)) {
          drawPyretRuntimeError();
        }
        else if(mkPred("ParseError")(e.exn)) {
          drawPyretParseError();
        } else {
          drawRuntimeErrorToString(e)();
        }
      }

      function drawUnknownException(e) {
        container.append($("<div>").text("An unexpected error occurred: " + String(e)));
      }

    });
  }

  return {
    drawError: drawError
  }

});
