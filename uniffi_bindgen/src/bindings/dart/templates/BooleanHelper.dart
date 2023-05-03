typedef BoolFfi = Bool;
typedef BoolDartFfi = bool;
typedef BoolLowered = Bool;
typedef BoolLifted = bool;

class FfiConverterBool {
    static BoolLifted lift(Api api, BoolLowered value) {
        return value != 0;
    }

    static int lower(BoolLifted value) {
        return value ? 1 : 0;
    }
}
