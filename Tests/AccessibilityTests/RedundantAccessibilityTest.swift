import Configuration
@testable import TestShared
import XCTest

final class RedundantAccessibilityTest: SPMSourceGraphTestCase {
    override static func setUp() {
        super.setUp()
        build(projectPath: AccessibilityProjectPath)
    }

    // MARK: - Fileprivate Access Tests

    func testFilePrivatePropertyInFilePrivateStruct() {
        index()
        assertRedundantAccessibility(.varInstance("fileprivateVarInFilePrivateStruct"))
    }

    func testFilePrivateFunctionInFilePrivateStruct() {
        index()
        assertRedundantAccessibility(.functionMethodInstance("fileprivateFuncInFilePrivateStruct()"))
    }

    // MARK: - Internal Access Tests

    func testInternalPropertyInInternalClass() {
        index()
        assertRedundantAccessibility(.varInstance("internalVarInInternalClass"))
    }

    func testInternalMethodInInternalClass() {
        index()
        assertRedundantAccessibility(.functionMethodInstance("internalFuncInInternalClass()"))
    }

    func testInternalStaticMethodInInternalEnum() {
        index()
        assertRedundantAccessibility(.functionMethodStatic("internalStaticMethodInInternalEnum()"))
    }

    // MARK: - Public Access Tests (members default to internal, not public)

    func testPublicPropertyInPublicStructNotFlagged() {
        // public var in public struct → NOT redundant (members default to internal)
        index()
        assertNotRedundantAccessibility(.varInstance("publicVarInPublicStruct"))
    }

    func testPublicFunctionInPublicStructNotFlagged() {
        // public func in public struct → NOT redundant (members default to internal)
        index()
        assertNotRedundantAccessibility(.functionMethodInstance("publicFuncInPublicStruct()"))
    }

    func testPublicPropertyInPublicClassNotFlagged() {
        // public var in public class → NOT redundant (members default to internal)
        index()
        assertNotRedundantAccessibility(.varInstance("publicVarInPublicClass"))
    }

    func testPublicFunctionInPublicClassNotFlagged() {
        // public func in public class → NOT redundant (members default to internal)
        index()
        assertNotRedundantAccessibility(.functionMethodInstance("publicFuncInPublicClass()"))
    }

    // MARK: - Extension Tests

    func testPublicFunctionInPublicExtensionNotFlagged() {
        // public func in public extension → NOT redundant (extension members default to internal)
        index()
        assertNotRedundantAccessibility(.functionMethodInstance("publicFuncInPublicExtension()"))
    }

    func testPublicExtensionOfPublicTypeNotFlagged() {
        // public extension of public type → NOT redundant (extension members default to internal)
        index()
        assertNotRedundantAccessibility(.extensionStruct("PublicStructWithPublicExtension"))
    }

    // MARK: - Negative Tests (Should NOT be flagged)

    func testImplicitInternalNotFlagged() {
        // var x: Int (implicit internal) in internal struct → NOT redundant
        index()
        assertNotRedundantAccessibility(.varInstance("implicitInternalVar"))
    }

    func testImplicitInternalFunctionNotFlagged() {
        index()
        assertNotRedundantAccessibility(.functionMethodInstance("implicitInternalFunc()"))
    }

    func testPublicVarInPrivateStructNotFlagged() {
        // public var in private struct → NOT redundant (different levels)
        index()
        assertNotRedundantAccessibility(.varInstance("publicVarInPrivateStruct"))
    }

    func testInternalVarInPrivateStructNotFlagged() {
        index()
        assertNotRedundantAccessibility(.varInstance("internalVar"))
    }

    func testPrivateVarInPublicClassNotFlagged() {
        // private var in public class → NOT redundant (different levels)
        index()
        assertNotRedundantAccessibility(.varInstance("privateVarInPublicClass"))
    }

    func testFilePrivateInInternalClassNotFlagged() {
        // fileprivate var in internal class → NOT redundant (different levels)
        index()
        assertNotRedundantAccessibility(.varInstance("fileprivateVarInInternalClass"))
    }

    func testPrivateVarInInternalClassNotFlagged() {
        // private var in internal class → NOT redundant (different levels)
        index()
        assertNotRedundantAccessibility(.varInstance("privateVar"))
    }

    // MARK: - Edge Cases

    func testNestedFilePrivateClassInFilePrivateClass() {
        // fileprivate class in fileprivate class
        index()
        assertRedundantAccessibility(.class("InnerFilePrivateClass"))
    }

    func testDeeplyNestedFilePrivateVar() {
        // fileprivate var in fileprivate class in fileprivate class
        index()
        assertRedundantAccessibility(.varInstance("deeplyNestedVar"))
    }

    // MARK: - Setter Modifier Tests

    func testPrivateRedundantPropInPrivateClass() {
        // private var in private class → REDUNDANT
        index()
        assertRedundantAccessibility(.varInstance("privateRedundantProp"))
    }

    func testPrivateWithPrivateSetFlagged() {
        // private private(set) var in private class → REDUNDANT (setter matches access)
        index()
        assertRedundantAccessibility(.varInstance("privateWithPrivateSet"))
    }

    func testFileprivateRedundantPropInFileprivateClass() {
        // fileprivate var in fileprivate class → REDUNDANT
        index()
        assertRedundantAccessibility(.varInstance("fileprivateRedundantProp"))
    }

    func testFileprivateWithPrivateSetFlagged() {
        // fileprivate private(set) var in fileprivate class → REDUNDANT (access matches parent, should be private(set))
        index()
        assertRedundantAccessibility(.varInstance("fileprivateWithPrivateSet"))
    }

    func testInternalRedundantPropInInternalClass() {
        // internal var in internal class → REDUNDANT
        index()
        assertRedundantAccessibility(.varInstance("internalRedundantProp"))
    }

    func testInternalWithPrivateSetFlagged() {
        // internal private(set) var in internal class → REDUNDANT (internal access is redundant)
        index()
        assertRedundantAccessibility(.varInstance("internalWithPrivateSet"))
    }

    func testInternalWithFileprivateSetFlagged() {
        // internal fileprivate(set) var in internal class → REDUNDANT (internal access is redundant)
        index()
        assertRedundantAccessibility(.varInstance("internalWithFileprivateSet"))
    }

    func testPublicWithInternalSetNotFlagged() {
        // public internal(set) var → NOT redundant (has setter modifier)
        index()
        assertNotRedundantAccessibility(.varInstance("publicWithInternalSet"))
    }

    func testPublicWithPrivateSetNotFlagged() {
        // public private(set) var → NOT redundant (has setter modifier)
        index()
        assertNotRedundantAccessibility(.varInstance("publicWithPrivateSet"))
    }

    // MARK: - Redundant Setter Modifier Tests (New Feature)

    func testFileprivateFileprivateSetInFileprivateClass() {
        // fileprivate fileprivate(set) in fileprivate class → REDUNDANT
        index()
        assertRedundantAccessibility(.varInstance("fileprivateRedundantSetterAndAccess"))
    }

    func testFileprivatePrivateSetInFileprivateClass() {
        // fileprivate private(set) in fileprivate class → REDUNDANT (access is redundant)
        index()
        assertRedundantAccessibility(.varInstance("fileprivateRedundantAccessOnly"))
    }

    func testFileprivateFileprivateSetInInternalClass() {
        // fileprivate fileprivate(set) in internal class → REDUNDANT (setter is redundant)
        index()
        assertRedundantAccessibility(.varInstance("fileprivateRedundantSetter"))
    }

    func testInternalInternalSetInInternalClass() {
        // internal internal(set) in internal class → REDUNDANT
        index()
        assertRedundantAccessibility(.varInstance("internalRedundantSetterAndAccess"))
    }

    func testInternalSetWithImplicitInternalInInternalClass() {
        // internal(set) with implicit internal access in internal class → REDUNDANT
        index()
        assertRedundantAccessibility(.varInstance("internalRedundantSetterImplicitAccess"))
    }

    func testInternalPrivateSetInInternalClass() {
        // internal private(set) in internal class → REDUNDANT (access is redundant)
        index()
        assertRedundantAccessibility(.varInstance("internalRedundantAccessOnly"))
    }

    func testFileprivatePrivateSetInInternalClassNotFlagged() {
        // fileprivate private(set) in internal class → NOT redundant
        index()
        assertNotRedundantAccessibility(.varInstance("fileprivatePrivateSetNonRedundant"))
    }

    func testPrivatePrivateSetInPrivateClass() {
        // private private(set) in private class → REDUNDANT
        index()
        assertRedundantAccessibility(.varInstance("privateRedundantSetterAndAccess"))
    }
}
