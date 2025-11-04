// Simple Node.js application for RailPack example
console.log("Hello World from RailPack!");
console.log("Current date:", new Date().toISOString());
console.log("Container running successfully!");

// Keep the process running
setInterval(() => {
  console.log("Heartbeat:", new Date().toISOString());
}, 60000); // Every 60 seconds
