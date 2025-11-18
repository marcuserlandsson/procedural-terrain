extends Camera3D

@export var move_speed: float = 10.0
@export var mouse_sensitivity: float = 0.003
@export var fast_move_speed: float = 30.0

var rotation_x: float = -PI/2  # Start looking straight down
var rotation_y: float = 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Initialize camera to look straight down
	rotation.x = rotation_x
	rotation.y = rotation_y

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, -PI/2, PI/2)
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta):
	# Update rotation
	rotation.y = rotation_y
	rotation.x = rotation_x
	
	# Get movement direction
	var direction = Vector3.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		direction += transform.basis.z
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		direction += transform.basis.x
	
	# Vertical movement
	if Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		direction -= Vector3.UP
	
	# Normalize and apply speed
	if direction.length() > 0:
		direction = direction.normalized()
		var speed = fast_move_speed if Input.is_key_pressed(KEY_SHIFT) else move_speed
		global_position += direction * speed * delta

