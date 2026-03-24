package engine

import "core:testing"

// Engine implemented using rotational dynamics.
// torque = moment of inertia (kg*m^2) * angular acceleration (rad/s^2)
// the moment of inertia resists changes in angular velocity (rpm).
// engine has an intrinsic moment of inertia that is a property of the engine itself and can be modelled as a constant value. 

// However, the effective moment of inertia seen by the engine changes with gear because wheel inertia is reflected through the gear ratio.
// Ieffective = Iengine + Iwheel * (gear_ratio)^2
// where Iengine is the intrinsic moment of inertia of the engine, Iwheel is the moment of inertia of the wheel, and gear_ratio is the ratio of the current gear.
// we can also add Idrivershaft, Iclutch, Itransmission, etc. to the effective moment of inertia if we want to model those components as well.

TorqueCurvePoint :: struct {
    // rpm is in rev/min
	rpm: int,
    // torque is in Nm
    torque: int,

}

// The engine produces torque, not force and not power directly.
// Engine torque depends on RPM, and the relationship is defined by the torque curve.
get_torque_for_rpm :: proc (curve: ^[dynamic]TorqueCurvePoint, rpm: int) -> int {
    prev_point : TorqueCurvePoint
    post_point : TorqueCurvePoint
    for point in curve {
        if point.rpm == rpm {
            return point.torque
        }
        if point.rpm < rpm {
            prev_point = point
        } else {
            post_point = point
            break
        }
    }
    return prev_point.torque + (post_point.torque - prev_point.torque) * (rpm - prev_point.rpm) / (post_point.rpm - prev_point.rpm)
}

@(test)
get_torque_for_rpm_test :: proc(t: ^testing.T) {
    torque_curve := make([dynamic]TorqueCurvePoint, 0, 10)
    defer delete(torque_curve)

    // very important torque curve is created sorted by rpm
    append(&torque_curve, TorqueCurvePoint{rpm = 4000, torque = 200})
    append(&torque_curve, TorqueCurvePoint{rpm = 8000, torque = 450})
    append(&torque_curve, TorqueCurvePoint{rpm = 12000, torque = 600})
    append(&torque_curve, TorqueCurvePoint{rpm = 15000, torque = 500})

    // linear interpolation between 4000 and 8000 rpm
    testing.expect_value(t, get_torque_for_rpm(&torque_curve, 5000), 262)
    testing.expect_value(t, get_torque_for_rpm(&torque_curve, 12000), 600)
    testing.expect_value(t, get_torque_for_rpm(&torque_curve, 15000), 500)
}