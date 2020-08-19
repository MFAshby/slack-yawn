slack-yawn
==========

Slack, reimagined in godot for some perverse reason. A work tool built in a game engine! 

Usage: 
* Get hold of a slack token, just re-use the method from [slack-term](https://erroneousboat.github.io/slack-term-auth/)
* Add the token as an environment variable `SLACK_TOKEN` to your system
* Clone the project, import it into godot and run. 

Features: 
Not much, you can read channels IMs and respond.

TODO:
* Keyboard controls, mostly ctrl+k to select a conversation. - this is actually really useful for testing, do this next DONE
* Clean up Slack.gd a bit. There's a lot of nesting, there's a lot of ugliness that should be pulled out into functions. Do it.
* Fixup the layout. Text box height should be fixed probably, or wrap to the message content. App should scale ok on various screens
* Emoji
* @people
* Groups
* Star and unstar channels
* Proper auth
* HTTP request queue (instead of a ton of separate HTTPRequest nodes that hang around forev)
* Dumb splash screen while initial bootup is happening
* Better error handling, probably display a toast or something
* Search all channels, join them
* Start new IMs 
* Chat indicators

BUGS: 
* Conversation scrolling
* Focus the text entry
* Hide channels I'm not a member of

