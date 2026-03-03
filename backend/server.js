import express from 'express';
import { MongoClient } from 'mongodb';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import dns from "node:dns/promises";
dns.setServers(["1.1.1.1"]);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// MongoDB Connection
const url = 'mongodb+srv://orlando:34313431@do2d.ypoboeu.mongodb.net/';
const client = new MongoClient(url);
const dbName = 'expense';
const collectionName = 'user0';

let collection;

async function connectToMongo() {
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        const db = client.db(dbName);
        collection = db.collection(collectionName);
    } catch (error) {
        console.error('Failed to connect to MongoDB', error);
    }
}

// Routes
app.get('/api/expenses', async (req, res) => {
    try {
        const findResult = await collection.find({}).toArray();
        res.json(findResult);
    } catch (error) {
        res.status(500).json({ error: 'Failed to fetch expenses' });
    }
});

app.post('/api/expenses', async (req, res) => {
    try {
        const { description, amount } = req.body;
        if (!description || !amount) {
            return res.status(400).json({ error: 'Description and amount are required' });
        }
        const result = await collection.insertOne({
            description,
            amount: parseFloat(amount),
            date: new Date()
        });
        res.status(201).json(result);
    } catch (error) {
        res.status(500).json({ error: 'Failed to add expense' });
    }
});

app.listen(port, async () => {
    await connectToMongo();
    console.log(`Server listening at http://localhost:${port}`);
});
