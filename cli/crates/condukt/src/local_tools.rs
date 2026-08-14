//! The local tool set shared by every Condukt host.
//!
//! Keeping registration and dispatch in one place prevents the interactive,
//! non-interactive, and protocol hosts from silently exposing different tools.

use std::{path::PathBuf, sync::Arc};

use condukt_inference::ToolDefinition;
use condukt_session::ToolDispatcher;
use condukt_tools::{BashTool, ReadTool, Tool};

pub struct LocalToolSet {
    definitions: Arc<Vec<ToolDefinition>>,
    tools: Vec<Box<dyn Tool>>,
}

impl LocalToolSet {
    pub fn new(root: PathBuf) -> Self {
        let tools: Vec<Box<dyn Tool>> = vec![
            Box::new(ReadTool { root: root.clone() }),
            Box::new(BashTool {
                root,
                ..BashTool::default()
            }),
        ];
        let definitions = Arc::new(tools.iter().map(|tool| tool.definition()).collect());
        Self { definitions, tools }
    }

    pub fn definitions(&self) -> Arc<Vec<ToolDefinition>> {
        Arc::clone(&self.definitions)
    }

    pub fn execute(&self, name: &str, arguments_json: &str) -> Result<String, String> {
        let tool = self
            .tools
            .iter()
            .find(|tool| tool.name() == name)
            .ok_or_else(|| format!("unknown tool '{name}'"))?;
        let arguments = serde_json::from_str(arguments_json)
            .map_err(|error| format!("invalid arguments for {name}: {error}"))?;
        tool.execute(&arguments)
    }
}

impl ToolDispatcher for LocalToolSet {
    fn dispatch(&self, name: &str, arguments_json: &str) -> Result<String, String> {
        self.execute(name, arguments_json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_the_same_registered_tools_to_every_host() {
        let tools = LocalToolSet::new(std::env::temp_dir());
        let definitions = tools.definitions();
        let names: Vec<_> = definitions
            .iter()
            .map(|definition| definition.name.as_str())
            .collect();
        assert_eq!(names, ["read", "bash"]);
    }
}
