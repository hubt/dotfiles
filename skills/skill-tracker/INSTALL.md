
To install this skill add this snippet to your ~/.claude/settings.json
with the appropriate path the track.go must be compiled into the track.
So you do need golang tools installed.

{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/hubt/.claude/skills/skill-tracker/track",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/hubt/.claude/skills/skill-tracker/track",
            "async": true
          }
        ]
      }
    ]
  }
}
