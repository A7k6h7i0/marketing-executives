import { PrismaClient, Role, Grade, TrackingStartPoint, AttendanceStatus, BreakType, BreakStatus, SyncStatus, IncidentType, ResolutionStatus, LeadStatus, RouteStatus } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  console.log("Seeding started...");

  // Clear database
  await prisma.telecallerCall.deleteMany();
  await prisma.telecallerLead.deleteMany();
  await prisma.rating.deleteMany();
  await prisma.visit.deleteMany();
  await prisma.lead.deleteMany();
  await prisma.optimizedRoute.deleteMany();
  await prisma.incident.deleteMany();
  await prisma.dailyPlan.deleteMany();
  await prisma.gpsPing.deleteMany();
  await prisma.break.deleteMany();
  await prisma.attendance.deleteMany();
  await prisma.outlet.deleteMany();
  await prisma.user.deleteMany();

  console.log("Database cleared.");

  // 2. Create default users
  const passwordHash = await bcrypt.hash("Password123!", 10);

  const admin = await prisma.user.create({
    data: {
      email: "admin@fieldforce.com",
      phone: "+15551112222",
      name: "Super Admin",
      passwordHash,
      role: Role.SUPER_ADMIN,
      status: "ACTIVE",
    },
  });

  const manager = await prisma.user.create({
    data: {
      email: "manager@fieldforce.com",
      phone: "+15553334444",
      name: "Regional Manager",
      passwordHash,
      role: Role.REGIONAL_MANAGER,
      region: "North",
      status: "ACTIVE",
    },
  });

  const executive = await prisma.user.create({
    data: {
      email: "executive@fieldforce.com",
      phone: "+15555556666",
      name: "Sales Executive",
      passwordHash,
      role: Role.SALES_EXECUTIVE,
      region: "North",
      status: "ACTIVE",
    },
  });

  const telecaller = await prisma.user.create({
    data: {
      email: "telecaller@fieldforce.com",
      phone: "+919876543210",
      name: "Ravi Telecaller",
      passwordHash,
      role: Role.TELECALLER,
      status: "ACTIVE",
    },
  });

  console.log("Users created:", {
    admin: admin.email,
    manager: manager.email,
    executive: executive.email,
    telecaller: telecaller.email,
  });

  // 3. Create mock outlets
  const outlets = await Promise.all([
    prisma.outlet.create({
      data: {
        name: "Downtown Supermarket",
        address: "123 Main Street, Downtown North",
        contactPhone: "+15550000001",
        contactEmail: "downtown@supermarket.com",
        gpsLat: 40.7128,
        gpsLng: -74.0060,
        grade: Grade.A,
        overallRating: 4.8,
      },
    }),
    prisma.outlet.create({
      data: {
        name: "Westside Grocery Hub",
        address: "789 Broadway Ave, Westside North",
        contactPhone: "+15550000002",
        contactEmail: "westside@groceryhub.com",
        gpsLat: 40.7138,
        gpsLng: -74.0080,
        grade: Grade.B,
        overallRating: 3.5,
      },
    }),
    prisma.outlet.create({
      data: {
        name: "Northside Pharmacy",
        address: "456 High Street, Northside North",
        contactPhone: "+15550000003",
        contactEmail: "northside@pharmacy.com",
        gpsLat: 40.7150,
        gpsLng: -74.0040,
        grade: Grade.C,
        overallRating: 2.8,
      },
    }),
  ]);

  console.log(`Created ${outlets.length} master outlets.`);

  // 4. Create a Daily Plan for today
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const plan = await prisma.dailyPlan.create({
    data: {
      userId: executive.id,
      routeId: "route-downtown",
      areaName: "Downtown Retail Zone",
      plannedVisits: 3,
      completedVisits: 0,
      planDate: today,
    },
  });

  console.log("Created Daily Plan for executive today:", plan.areaName);

  // 5. Sample telecaller leads
  await prisma.telecallerLead.createMany({
    data: [
      {
        name: "Ravi Kumar",
        phone: "9876543210",
        company: "ABC Traders",
        email: "ravi@example.com",
        status: "NEW",
        ownerId: telecaller.id,
        source: "seed",
        notes: "Interested in product demo",
      },
      {
        name: "Priya Sharma",
        phone: "9123456780",
        company: "Westside Retail",
        status: "FOLLOWUP",
        ownerId: telecaller.id,
        source: "seed",
        nextFollowAt: new Date(),
      },
      {
        name: "Amit Patel",
        phone: "9988776655",
        company: "Patel Distributors",
        status: "CONTACTED",
        ownerId: telecaller.id,
        source: "seed",
      },
    ],
  });

  console.log("Seeding successfully completed!");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
