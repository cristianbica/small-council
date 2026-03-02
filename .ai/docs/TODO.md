# TODO

This a list of bugs and todos. These will be handled on demand as I ask for them to be fixed / implmented. This is not a backlog or roadmap — just a scratchpad for current known issues and tasks.

## Scribe summary not streamed to chat

When Scribe automaticallty generates a summary at the end of the conversation, that summary is not streamed to the chat, but only appears if I refresh the page.


## Allow changing model per-cenversation or even per-advisor in a conversation

This would allow more flexibility and better cost management, as users could choose to use cheaper models for some conversations or advisors, and more powerful models for others.
For example in usual scenarios I'd use a cheaper model. For for something more involved I'd like to switch all advisors in a conversation to a more powerful model. And for something really important I'd like to be able to switch to the best model available, even if it's expensive, just for that conversation for a particular advisor.
It would also allow users to experiment with different models and see how they perform in different scenarios.

## Use a a diff gem instead of our own diff implementation

For example https://github.com/samg/diffy


## Ability to show resources in chat

For example if I instruct the scribe to create a memory in the response I should see a memory card (short) but be able to click and see the whole memory in a popup (should this be the default?)


## Conversation tools usage

When asking scribe to do an action similar with another one it previously did the scribe tells me it did the new action but in fact it didn't. Perhaps it believes so as we're passing the whole converstion. what strategies could we adopt here? how others are doing it?

## Advisors answer all at once

They should take turns so I can actually see their answers


## View model interactions as they happen

Current model interactions are visible after the advisor has responded. I should be able to see them as they happen, especially for long responses. This would allow me to understand better what the model is doing and if it's going in the right direction. It would also allow me to stop it if I see it's going in the wrong direction.

## Address possible bias in responses

On discussions I get the impression that advisors are getting biased by previous messages in the conversation from other advisorsx.


## Control for long answers / thinking from advisors

When an advisor is taking too long to respond I should be able to see that and decide if I want to wait or stop it. This would allow me to have more control over the conversation and avoid waiting for a response that might never come. Additionally there should be a limit on how many interactions should be allowed between the system and the model.
