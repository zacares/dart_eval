import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/fpl.dart';
import 'package:dart_eval/src/eval/compiler/helpers/return.dart';
import 'package:dart_eval/src/eval/compiler/scope.dart';
import 'package:dart_eval/src/eval/compiler/statement/block.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/util.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

int compileMethodDeclaration(MethodDeclaration d, CompilerContext ctx,
    NamedCompilationUnitMember parent) {
  ctx.runPrescan(d);
  final b = d.body;
  final parentName = parent.name.value() as String;
  final methodName = d.name.value() as String;
  final pos = beginMethod(ctx, d, d.offset, '$parentName.$methodName()');

  ctx.beginAllocScope(existingAllocLen: (d.parameters?.parameters.length ?? 0));
  ctx.scopeFrameOffset += d.parameters?.parameters.length ?? 0;
  ctx.setLocal(
      '#this',
      Variable(
          0,
          ctx.visibleTypes[ctx.library]![
              ctx.currentClass!.name.value() as String]!));
  final resolvedParams = d.parameters == null
      ? <PossiblyValuedParameter>[]
      : resolveFPLDefaults(ctx, d.parameters!, true, allowUnboxed: true);

  if (b.isAsynchronous) {
    setupAsyncFunction(ctx);
  }

  var i = d.isStatic ? 0 : 1;

  for (final param in resolvedParams) {
    final p = param.parameter;
    Variable Vrep;

    p as SimpleFormalParameter;
    var type = CoreTypes.dynamic.ref(ctx);
    if (p.type != null) {
      type = TypeRef.fromAnnotation(ctx, ctx.library, p.type!)
          .copyWith(boxed: true);
    }
    Vrep = Variable(i, type)..name = p.name!.value() as String;

    ctx.setLocal(Vrep.name!, Vrep);

    i++;
  }

  StatementInfo? stInfo;
  if (b is BlockFunctionBody) {
    stInfo = compileBlock(
        b.block,
        AlwaysReturnType.fromAnnotation(
            ctx, ctx.library, d.returnType, CoreTypes.dynamic.ref(ctx)),
        ctx,
        name: '$methodName()');
  } else if (b is ExpressionFunctionBody) {
    ctx.beginAllocScope();
    final V = compileExpression(b.expression, ctx);
    stInfo = doReturn(
        ctx,
        AlwaysReturnType.fromAnnotation(
            ctx, ctx.library, d.returnType, CoreTypes.dynamic.ref(ctx)),
        V,
        isAsync: b.isAsynchronous);
    ctx.endAllocScope();
  } else if (b is EmptyFunctionBody) {
    return -1;
  } else {
    throw CompileError('Unknown function body type ${b.runtimeType}');
  }

  ctx.endAllocScope();

  if (!(stInfo.willAlwaysReturn || stInfo.willAlwaysThrow)) {
    if (b.isAsynchronous) {
      asyncComplete(ctx, -1);
    } else {
      ctx.pushOp(Return.make(-1), Return.LEN);
    }
  }

  if (d.isStatic) {
    ctx.topLevelDeclarationPositions[ctx.library]!['$parentName.$methodName'] =
        pos;
  } else {
    final mapIndex = d.isGetter
        ? 0
        : d.isSetter
            ? 1
            : 2;
    ctx.instanceDeclarationPositions[ctx.library]![parentName]![mapIndex]
        [methodName] = pos;
  }

  return pos;
}
