# res://scenes/ui/pause_menu.gd
extends CanvasLayer

# Emitido cuando el jugador elige una acción del menú.
# Usamos señales para no acoplar el menú a game.gd directamente.
signal resume_requested
signal disconnect_requested
signal quit_requested

@onready var panel          = $Panel
@onready var btn_resume     = $Panel/VBox/BtnResume
@onready var btn_disconnect = $Panel/VBox/BtnDisconnect
@onready var btn_quit       = $Panel/VBox/BtnQuit
@onready var label_role     = $Panel/VBox/LabelRole

func _ready():
	# Ocultamos el menú al inicio; lo muestra game.gd cuando llega Escape
	hide()
	_update_buttons()

func show_menu():
	_update_buttons()
	show()
	# Liberamos el mouse para que el jugador pueda hacer clic
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func hide_menu():
	hide()
	# Volvemos a capturar el mouse para el movimiento de cámara
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Ajusta los textos y visibilidad de botones según el rol actual
func _update_buttons():
	var is_server = multiplayer.is_server()
	var has_peer  = multiplayer.multiplayer_peer != null

	if has_peer:
		if is_server:
			label_role.text      = "Rol: Host"
			btn_disconnect.text  = "Cerrar sesión (Host)"
		else:
			label_role.text      = "Rol: Cliente"
			btn_disconnect.text  = "Desconectarse"
		btn_disconnect.show()
	else:
		# Modo debug solo: no hay red, no tiene sentido desconectarse
		label_role.text = "Modo: Solo (debug)"
		btn_disconnect.hide()

func _on_btn_resume_pressed():
	resume_requested.emit()

func _on_btn_disconnect_pressed():
	disconnect_requested.emit()

func _on_btn_quit_pressed():
	quit_requested.emit()
