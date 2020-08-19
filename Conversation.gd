extends ItemList

var userRegex = RegEx.new()

# Called when the node enters the scene tree for the first time.
func _ready():
	Slack.connect("state_changed", self, "_state_changed")
	userRegex.compile("<@([a-zA-Z0-9]{9})>")
	
class TimestampSorter:
	static func sort_by_ts_desc(a, b):
		return a["ts"] < b["ts"]
		
func _state_changed(old_state, new_state):
	self.clear()
	var nc = Slack.fd(new_state, ["selected_conversation"])
	if nc == null:
		self.add_item("No conversation selected!")
	else:
		var idx = 0
		var messages = Slack.fd(new_state, ["messages", nc])
		if messages == null:
			self.add_item("Loading...")
		else:
			var ix = 0
			messages = messages.values()
			messages.sort_custom(TimestampSorter, "sort_by_ts_desc")
			for i in len(messages):
				self._add_message(ix, messages[i], new_state)
				ix += 1
			var pms = new_state.pending_messages.values()
			for i in len(pms):
				var pm = pms[i]
				if pm != null:
					if pm.channel == nc:
						self._add_message(ix, pm, new_state)
						ix += 1
			self.select(ix-1)
			self.ensure_current_is_visible()
			self.unselect_all()

func _add_message(i, msg, state):
	# Start with just the message text
	var txt: String = msg.text
	
	# Prepend the sender's name
	if msg.has("user"):
		var senderName = Slack.fd(state, ["users", msg.user, "name"])
		txt = senderName + ": " + txt
	
	# Parse the message for user IDs and 
	# replace with usernames 
	var um = userRegex.search_all(txt)
	for m in um:
		var repl = m.get_string()
		var userId = m.get_string(1)
		var userName = Slack.fd(state, ["users", userId, "name"])
		txt = txt.replacen(repl, "@" + userName)
	
	self.add_item(txt)
	self.set_item_metadata(i, msg)
