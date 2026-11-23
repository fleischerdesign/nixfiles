type ToolResult = { content: string }

type ToolDefinition = {
  name: string
  description: string
  options?: { codemode: boolean }
  input: { type: 'object'; properties: object; additionalProperties: false }
  execute: () => Promise<ToolResult>
}

type ToolList = { add: (tool: ToolDefinition) => void }

type PluginContext = {
  tool: { transform: (edit: (tools: ToolList) => void) => Promise<void> }
}

export default {
  id: 'fleet-opencode-tools',
  setup: async (ctx: PluginContext) => {
    await ctx.tool.transform((tools) => {
      tools.add({
        name: 'fleet_runtime',
        description: 'Reports the OpenChamber runtime host and working directory for this session.',
        options: { codemode: false },
        input: { type: 'object', properties: {}, additionalProperties: false },
        async execute() {
          const host = process.env.HOSTNAME || process.env.HOST || 'unknown'
          return { content: `runtime host: ${host}\nworking directory: ${process.cwd()}` }
        },
      })
    })
  },
}
