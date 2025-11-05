import codeql.ruby.AST

/**
 * Reports call sites that invoke Ruby code-execution primitives.
 */
private predicate hasConstantReceiver(MethodCall call, string name) {
  exists(ConstantReadAccess recv |
    call.getReceiver() = recv and recv.getName() = name
  )
}

private predicate isEvalLikePrimitive(MethodCall call) {
  call.getMethodName() in [
    "eval",
    "instance_eval",
    "class_eval",
    "module_eval",
    "instance_exec",
    "class_exec",
    "module_exec"
  ]
}

private predicate isKernelPrimitive(MethodCall call) {
  call.getMethodName() in ["exec", "system", "spawn"] and hasConstantReceiver(call, "Kernel")
}

private predicate isProcessPrimitive(MethodCall call) {
  call.getMethodName() in ["exec", "spawn"] and hasConstantReceiver(call, "Process")
}

private predicate isIOPrimitive(MethodCall call) {
  call.getMethodName() in ["popen", "popen2", "popen3", "popen4"] and hasConstantReceiver(call, "IO")
}

private predicate isOpen3Primitive(MethodCall call) {
  call.getMethodName() in [
    "popen2",
    "popen2e",
    "popen3",
    "capture2",
    "capture2e",
    "capture3",
    "pipeline",
    "pipeline_r",
    "pipeline_rw",
    "pipeline_start"
  ] and hasConstantReceiver(call, "Open3")
}

from MethodCall call
where
  isEvalLikePrimitive(call) or
  isKernelPrimitive(call) or
  isProcessPrimitive(call) or
  isIOPrimitive(call) or
  isOpen3Primitive(call)
select call, "Call to code execution primitive \"" + call.getMethodName() + "\"."
