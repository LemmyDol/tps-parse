const fs = require("fs");
const path = require("path");

const mysqlPackageDir = process.env.MYSQL_PACKAGE_DIR || "D:/Label Pro/Label Pro Database/mysql_package";
const mysqlModulePath = path.join(mysqlPackageDir, "node_modules", "mysql2", "promise");
const mysql = require(mysqlModulePath);

const mappingPath = process.env.TABLE_MAPPING_PATH || path.join(mysqlPackageDir, "table_mapping.json");
const outputJsonPath = process.env.ROWCOUNT_REPORT_JSON || path.resolve("D:/Label Pro/tps-parse/out-test/mysql-rowcount-report.json");
const outputTextPath = process.env.ROWCOUNT_REPORT_TXT || path.resolve("D:/Label Pro/tps-parse/out-test/mysql-rowcount-report.txt");

function qid(name) {
  return `\`${String(name).replace(/`/g, "``")}\``;
}

async function main() {
  const mapping = JSON.parse(fs.readFileSync(mappingPath, "utf8"));
  const database = process.env.MYSQL_DATABASE || mapping.database || "labelpro_restored";

  const conn = await mysql.createConnection({
    host: process.env.MYSQL_HOST || "127.0.0.1",
    port: Number(process.env.MYSQL_PORT || 3306),
    user: process.env.MYSQL_USER || "root",
    password: process.env.MYSQL_PASSWORD || "",
    database,
  });

  try {
    const results = [];

    for (const table of mapping.tables) {
      const sql = `SELECT COUNT(1) AS c FROM ${qid(table.table_name)}`;
      const [rows] = await conn.query(sql);
      const mysqlRows = Number(rows[0].c || 0);
      const csvRows = Number(table.row_count || 0);
      results.push({
        csv_file: table.csv_file,
        table_name: table.table_name,
        csv_rows: csvRows,
        mysql_rows: mysqlRows,
        delta: mysqlRows - csvRows,
        status: mysqlRows === csvRows ? "match" : "mismatch",
      });
    }

    const mismatches = results.filter((r) => r.status === "mismatch");
    const matches = results.length - mismatches.length;

    fs.mkdirSync(path.dirname(outputJsonPath), { recursive: true });
    fs.writeFileSync(
      outputJsonPath,
      JSON.stringify(
        {
          database,
          generated_at: new Date().toISOString(),
          table_count: results.length,
          matches,
          mismatches: mismatches.length,
          results,
        },
        null,
        2
      ),
      "utf8"
    );

    const lines = [];
    lines.push(`Database: ${database}`);
    lines.push(`Tables checked: ${results.length}`);
    lines.push(`Matches: ${matches}`);
    lines.push(`Mismatches: ${mismatches.length}`);
    lines.push("");
    lines.push("Mismatches:");
    if (mismatches.length === 0) {
      lines.push("None");
    } else {
      for (const row of mismatches.sort((a, b) => a.table_name.localeCompare(b.table_name))) {
        lines.push(`- ${row.table_name} | csv=${row.csv_rows} mysql=${row.mysql_rows} delta=${row.delta} | file=${row.csv_file}`);
      }
    }

    fs.writeFileSync(outputTextPath, lines.join("\n"), "utf8");

    console.log(`Database: ${database}`);
    console.log(`Tables checked: ${results.length}`);
    console.log(`Matches: ${matches}`);
    console.log(`Mismatches: ${mismatches.length}`);
    console.log(`Report: ${outputTextPath}`);
  } finally {
    await conn.end();
  }
}

main().catch((err) => {
  console.error(err.message || String(err));
  process.exit(1);
});
