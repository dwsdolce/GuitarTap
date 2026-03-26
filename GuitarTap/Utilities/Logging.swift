// Debug logging utility for TAP_DEBUG statements
// This must be set to true in the Build settings of the projeect under Swift Compiler - Custom Flags/Active Compilation Conditions/DEBUG
#if ENABLE_TAP_DEBUG
public func TAP_DEBUG(_ category: String, _ message: @autoclosure () -> String) {
    print("TAP_DEBUG [\(category)] \(message())")
}
#else
public func TAP_DEBUG(_ category: String, _ message: @autoclosure () -> String) {}
#endif
