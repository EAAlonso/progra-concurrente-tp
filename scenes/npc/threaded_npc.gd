extends Node3D

func apply_simulation_state(next_position: Vector3, next_rotation_y: float):
	position = next_position
	rotation.y = next_rotation_y
