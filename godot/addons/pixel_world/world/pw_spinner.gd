@tool
extends Node3D
## 绕自身 Z 轴匀速转动（风车叶片等）。speed：每秒转多少弧度。

@export var speed := 0.6


func _process(delta: float) -> void:
	rotate_object_local(Vector3.BACK, speed * delta)
