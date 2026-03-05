Based on the tools currently implemented in

agent.rb
, you can ask the agent prompts that involve general conversation, math calculations, and reading the local file system.

Here are some example prompts you can try:

1. General Conversation & Knowledge:

"Hi, how are you?" (The agent will respond directly without tools)
"Tell me a short joke."
2. Math Calculations (using the calculate tool):

"What is 45 + 23?"
"Calculate 15% of 850."
"What is the square root of 256 multiplied by 10?"
3. File System Interaction (using list_files and read_file tools):

"What files are in the current directory?"
"List the files in the 'project' folder."
"Read the contents of agent.rb and summarize what it does."
"Can you check if there is a README.md file here?"
4. Complex/Combined Tasks:

"List the files in this directory and calculate 12 * 12."
"Read agent.rb and tell me which models are set as the PLANNER_MODEL and EXECUTOR_MODEL."
The agent is designed to dynamically decide whether it needs to use a tool to fulfill your request or if it can answer you directly based on its general knowledge.