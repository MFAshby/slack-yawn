extends LineEdit

# OMG swap out the boring editor with this
# https://ash-k.itch.io/textreme-2
# pleeeease :) 

func _ready():
	self.connect("text_entered", self, "_text_entered")

func _text_entered(new_text):
	Slack.send_message(new_text)
	self.clear()
