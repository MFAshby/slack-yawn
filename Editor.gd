extends TextEdit

# OMG swap out the boring editor with this
# https://ash-k.itch.io/textreme-2
# pleeeease :) 

func _gui_input(event):
	# Ctrl modifier prevents the message being sent, 
	# Allowing multi-line entry
	if Input.is_action_pressed("ui_accept") and not event.get("control"):
		Slack.send_message(self.text)
		self.text = ""
		self.accept_event()
	
