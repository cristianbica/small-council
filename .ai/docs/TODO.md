# TODO

This a list of bugs and todos. These will be handled on demand as I ask for them to be fixed / implmented. This is not a backlog or roadmap — just a scratchpad for current known issues and tasks.


## Sender name for User in model messages is currently `user.to_s`

Noticed this in model interaction and found this code:
sender_name = msg.sender.respond_to?(:name) ? msg.sender.name : msg.sender.to_s

## Mentioning @all behaviour

Noticed 2 issues here:
- Scribe should not respond to @all mentions (currently does)
- Advisors should respond in order (currently all start "thinkning" at the same time, which is a bit chaotic)


## Advisors' models receives also "is thinking ..." messages

When debugging model interactions I noticed that the API is receiving "[ADVISOR_NAME] is thinking..." messages, which provides little to no value in the response

## Conversation UI is buggy

- I see multiple scrollbars everywhere
- those letters avatars are badly centered
- for message bubbles daisyui has proper support (chat-* classes) - see https://daisyui.com/llms.txt

## Implement tools to manager council and advisors

I can see a workflow where the user would create a space, start a conversation with the scribe and tell scribe what's the purpose of the space. The it can ask the scribe to propose a council(s) and advisors structure. After iterating on those the user might be fine with it and just ask the scribe to create the council and advisors based on the proposed structure. This would be a great way to leverage the scribe to do the initial setup of the council and advisors, which can be a bit tedious to do manually.

## Investigate RubyLLM::Agent

How would using RubyLLM::Agent help us? Can Scribe be an RubyLLM::Agent?
https://rubyllm.com/agents/
https://rubyllm.com/agentic-workflows/


## Scribe summary not streamed to chat

When Scribe automaticallty generates a summary at the end of the conversation, that summary is not streamed to the chat, but only appears if I refresh the page.


## Allow changing model per-cenversation or even per-advisor in a conversation

This would allow more flexibility and better cost management, as users could choose to use cheaper models for some conversations or advisors, and more powerful models for others.
For example in usual scenarios I'd use a cheaper model. For for something more involved I'd like to switch all advisors in a conversation to a more powerful model. And for something really important I'd like to be able to switch to the best model available, even if it's expensive, just for that conversation for a particular advisor.
It would also allow users to experiment with different models and see how they perform in different scenarios.

## Use a a diff gem instead of our own diff implementation

For example https://github.com/samg/diffy
