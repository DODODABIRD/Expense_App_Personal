const express = require("express");
const mongoose = require("mongoose");

const app = express();
app.use(express.json());

// ✅ MongoDB connection (cached for Vercel)
let isConnected = false;

async function connectDB() {
  if (isConnected) return;

  if (!process.env.MONGODB_URI) {
    throw new Error("MONGODB_URI is missing");
  }

  await mongoose.connect(process.env.MONGODB_URI);
  isConnected = true;
}

// ✅ User Schema

// TODO: Make the schema fit the expense schema
const ExpenseSchema = new mongoose.Schema(
  {
    localId: { type: String, required: true},
    name: { type: String, required: true },
    amount: {type: String, required: true},
    category: {type: String, required: true},
    type: {type: String, required: true},
    date: {type: String, required: true}
  },
  { timestamps: true }
);

const User = mongoose.models.User || mongoose.model("nigga", ExpenseSchema);


app 
/**
 * CREATE
 * POST /api/users
 */
app.post("/api/users", async (req, res) => {
  try {
    await connectDB();
    const user = await User.create(req.body);
    res.status(201).json(user);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

/**
 * READ (all)
 * GET /api/users
 */
app.get("/api/users", async (req, res) => {
  await connectDB();
  const users = await User.find();
  res.json(users);
});

/**
 * READ (one)
 * GET /api/users/:id
 */
app.get("/api/users/:id", async (req, res) => {
  await connectDB();
  const user = await User.findById(req.params.id);
  if (!user) return res.status(404).json({ message: "Not found" });
  res.json(user);
});

/**
 * UPDATE
 * PUT /api/users/:id
 */
app.put("/api/users/:id", async (req, res) => {
  await connectDB();
  const user = await User.findByIdAndUpdate(
    req.params.id,
    req.body,
    { new: true }
  );
  res.json(user);
});

/**
 * DELETE
 * DELETE /api/users/:id
 */
app.delete("/api/users/:id", async (req, res) => {
  await connectDB();
  await User.findByIdAndDelete(req.params.id);
  res.json({ message: "Deleted" });
});

module.exports = app;