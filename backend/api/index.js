import express from 'express';

const app = express();

app.get('/', (req, res) => {
  res.send('API running');
});

export default function handler(req, res){
  res.send("Expense API IS ALIVE");
};