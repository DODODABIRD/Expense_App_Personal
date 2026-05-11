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
const UserSchema = new mongoose.Schema(
  {
    name: { type: String, required: true },
  },
  { timestamps: true }
);

const User = mongoose.models.User || mongoose.model("User", UserSchema);

/**
 * CREATE
 * POST /api/users
 */
app.post("/users", async (req, res) => {
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
app.get("/users", async (req, res) => {
  await connectDB();
  const users = await User.find();
  res.json(users);
});

/**
 * READ (one)
 * GET /api/users/:id
 */
app.get("/users/:id", async (req, res) => {
  await connectDB();
  const user = await User.findById(req.params.id);
  if (!user) return res.status(404).json({ message: "Not found" });
  res.json(user);
});

/**
 * UPDATE
 * PUT /api/users/:id
 */
app.put("/users/:id", async (req, res) => {
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
app.delete("/users/:id", async (req, res) => {
  await connectDB();
  await User.findByIdAndDelete(req.params.id);
  res.json({ message: "Deleted" });
});

module.exports = app;