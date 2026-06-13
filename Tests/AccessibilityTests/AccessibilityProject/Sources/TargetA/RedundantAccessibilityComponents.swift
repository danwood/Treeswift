/**
 RedundantAccessibilityComponents.swift
 Test fixtures for redundant access modifier detection
 */

// MARK: - Fileprivate Access (Should be flagged)

fileprivate struct FilePrivateStructWithRedundantMembers {
    fileprivate var fileprivateVarInFilePrivateStruct: Int = 0  // REDUNDANT
    fileprivate func fileprivateFuncInFilePrivateStruct() {}    // REDUNDANT

    // NOT redundant - different access level
    private var privateVar: Int = 0
}

fileprivate func useFilePrivateStruct() {
    let fps = FilePrivateStructWithRedundantMembers()
    _ = fps.fileprivateVarInFilePrivateStruct
    fps.fileprivateFuncInFilePrivateStruct()
}

// MARK: - Internal Access (Should be flagged)

internal class InternalClassWithRedundantMembers {
    internal var internalVarInInternalClass: Int = 0  // REDUNDANT
    internal func internalFuncInInternalClass() {}     // REDUNDANT

    // NOT redundant - different access level
    private var privateVar: Int = 0
    fileprivate var fileprivateVar: Int = 0
}

fileprivate func useInternalClass() {
    let ic = InternalClassWithRedundantMembers()
    _ = ic.internalVarInInternalClass
    ic.internalFuncInInternalClass()
    _ = ic.fileprivateVar
}

internal enum InternalEnumWithRedundantMembers {
    case someCase

    internal static func internalStaticMethodInInternalEnum() {}  // REDUNDANT
}

fileprivate func useInternalEnum() {
    _ = InternalEnumWithRedundantMembers.someCase
    InternalEnumWithRedundantMembers.internalStaticMethodInInternalEnum()
}

// MARK: - Public Access (Should NOT be flagged - members default to internal)

public struct PublicStructWithExplicitMembers {
    public var publicVarInPublicStruct: Int = 0      // NOT redundant (members default to internal)
    public func publicFuncInPublicStruct() {}         // NOT redundant (members default to internal)

    // Also not redundant - different access levels
    internal var internalVar: Int = 0
    private var privateVar: Int = 0
}

public class PublicClassWithExplicitMembers {
    public var publicVarInPublicClass: Int = 0       // NOT redundant (members default to internal)
    public func publicFuncInPublicClass() {}          // NOT redundant (members default to internal)

    // Also not redundant - different access levels
    private var privateVarInPublicClass: Int = 0
}

// MARK: - Extension Tests

public struct PublicStructWithPublicExtension {
    public var someVar: Int = 0
}

public extension PublicStructWithPublicExtension {  // NOT redundant (extension members default to internal)
    public func publicFuncInPublicExtension() {}    // NOT redundant (extension members default to internal)
}

// MARK: - Negative Tests (Should NOT be flagged)

internal struct InternalStructWithImplicitMembers {
    var implicitInternalVar: Int = 0          // NOT redundant (implicit)
    func implicitInternalFunc() {}            // NOT redundant (implicit)
}

private struct PrivateStructWithMixedAccess {
    public var publicVarInPrivateStruct: Int = 0  // NOT redundant (different level)
    internal var internalVar: Int = 0              // NOT redundant (different level)
    var implicitPrivateVar: Int = 0                // NOT redundant (implicit)
}

internal class InternalClassWithMixedAccess {
    fileprivate var fileprivateVarInInternalClass: Int = 0  // NOT redundant
    private var privateVar: Int = 0                          // NOT redundant
}

// MARK: - Nested Type Tests

fileprivate class OuterFilePrivateClass {
    fileprivate class InnerFilePrivateClass {             // REDUNDANT
        fileprivate var deeplyNestedVar: Int = 0          // REDUNDANT
    }
}

fileprivate func useNestedClasses() {
    _ = OuterFilePrivateClass()
    let ifc = OuterFilePrivateClass.InnerFilePrivateClass()
    _ = ifc.deeplyNestedVar
}

// MARK: - Setter-Specific Modifier Tests

public class SetterModifierTests {
    // Test fileprivate properties in fileprivate nested class
    fileprivate class FileprivateNestedClass {
        fileprivate var fileprivateRedundantProp: Int = 0                  // REDUNDANT
        fileprivate private(set) var fileprivateWithPrivateSet: Int = 0    // NOT redundant (has setter modifier)

        func usePrivate() {
            // Access them to ensure they're used
            _ = fileprivateRedundantProp
            _ = fileprivateWithPrivateSet
        }
    }

    // Test internal properties with setter modifiers
    internal class InternalNestedClass {
        internal var internalRedundantProp: Int = 0                        // REDUNDANT
        internal private(set) var internalWithPrivateSet: Int = 0          // NOT redundant (has setter modifier)
        internal fileprivate(set) var internalWithFileprivateSet: Int = 0  // NOT redundant (has setter modifier)

        func usePrivate() {
            _ = internalRedundantProp
            _ = internalWithPrivateSet
            _ = internalWithFileprivateSet
        }
    }

    // Test public properties with setter modifiers
    public class PublicNestedClass {
        public var publicNotRedundantProp: Int = 0                         // NOT redundant (members default to internal)
        public internal(set) var publicWithInternalSet: Int = 0            // NOT redundant (has setter modifier)
        public private(set) var publicWithPrivateSet: Int = 0              // NOT redundant (has setter modifier)

        func usePrivate() {
            _ = publicNotRedundantProp
            _ = publicWithInternalSet
            _ = publicWithPrivateSet
        }
    }

    // Test private properties separately since they need private access
    private class PrivateNestedClass {
        private var privateRedundantProp: Int = 0                      // REDUNDANT
        private private(set) var privateWithPrivateSet: Int = 0        // NOT redundant (has setter modifier)

        func usePrivate() {
            _ = privateRedundantProp
            _ = privateWithPrivateSet
        }
    }

    func useAll() {
        let fnc = FileprivateNestedClass()
        fnc.usePrivate()

        let inc = InternalNestedClass()
        inc.usePrivate()

        let pub = PublicNestedClass()
        pub.usePrivate()

        let pnc = PrivateNestedClass()
        pnc.usePrivate()
    }
}

// MARK: - Redundant Setter Modifier Tests (New Feature)

class RedundantSetterModifierTests {
    // Case 1: fileprivate fileprivate(set) in fileprivate class
    fileprivate class FileprivateClass {
        fileprivate fileprivate(set) var fileprivateRedundantSetterAndAccess: Int = 0  // REDUNDANT: equivalent to "fileprivate", which is redundant with enclosing scope
        fileprivate private(set) var fileprivateRedundantAccessOnly: Int = 0  // REDUNDANT: "fileprivate" is redundant, should be "private(set)"

        func use() {
            _ = fileprivateRedundantSetterAndAccess
            _ = fileprivateRedundantAccessOnly
        }
    }

    // Case 2: Different parent scope cases
    internal class InternalClassWithSetters {
        fileprivate fileprivate(set) var fileprivateRedundantSetter: Int = 0  // REDUNDANT: setter is redundant, should be "fileprivate"
        internal internal(set) var internalRedundantSetterAndAccess: Int = 0  // REDUNDANT: equivalent to "internal", which is redundant with enclosing scope
        internal(set) var internalRedundantSetterImplicitAccess: Int = 0  // REDUNDANT: internal(set) with implicit internal access, equivalent to "internal", redundant with scope
        internal private(set) var internalRedundantAccessOnly: Int = 0  // REDUNDANT: "internal" is redundant, should be "private(set)"
        fileprivate private(set) var fileprivatePrivateSetNonRedundant: Int = 0  // NOT redundant: access differs from parent, setter differs from access

        func use() {
            _ = fileprivateRedundantSetter
            _ = internalRedundantSetterAndAccess
            _ = internalRedundantSetterImplicitAccess
            _ = internalRedundantAccessOnly
            _ = fileprivatePrivateSetNonRedundant
        }
    }

    // Case 3: private private(set) in private class
    private class PrivateClass {
        private private(set) var privateRedundantSetterAndAccess: Int = 0  // REDUNDANT: equivalent to "private", which is redundant with enclosing scope

        func use() {
            _ = privateRedundantSetterAndAccess
        }
    }

    func useAll() {
        let fpc = FileprivateClass()
        fpc.use()

        let ic = InternalClassWithSetters()
        ic.use()

        let pc = PrivateClass()
        pc.use()
    }
}

// Used to ensure these are referenced
public class RedundantAccessibilityComponents {
    public init() {
        useFilePrivateStruct()
        useInternalClass()
        useInternalEnum()
        useNestedClasses()

        let ps = PublicStructWithExplicitMembers()
        _ = ps.publicVarInPublicStruct
        ps.publicFuncInPublicStruct()
        _ = ps.internalVar

        let pcls = PublicClassWithExplicitMembers()
        _ = pcls.publicVarInPublicClass
        pcls.publicFuncInPublicClass()

        let pse = PublicStructWithPublicExtension()
        _ = pse.someVar
        pse.publicFuncInPublicExtension()

        let ii = InternalStructWithImplicitMembers()
        _ = ii.implicitInternalVar
        ii.implicitInternalFunc()

        let pma = PrivateStructWithMixedAccess()
        _ = pma.publicVarInPrivateStruct
        _ = pma.internalVar
        _ = pma.implicitPrivateVar

        let ima = InternalClassWithMixedAccess()
        _ = ima.fileprivateVarInInternalClass

        let smt = SetterModifierTests()
        smt.useAll()

        let rsmt = RedundantSetterModifierTests()
        rsmt.useAll()
    }
}
