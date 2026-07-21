import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { LeadStatus, Role } from "@prisma/client";
import axios from "axios";

// Helper for mocked nearby leads when Google Places is unconfigured
const getMockNearbyLeads = (lat: number, lng: number, category: string) => {
  const cat = category || "retail";
  return [
    {
      placeId: "mock-place-1",
      businessName: `Metro ${cat.charAt(0).toUpperCase() + cat.slice(1)} Mart`,
      businessCategory: cat,
      contactPhone: "+1 (555) 019-2831",
      contactEmail: `info@metromart-${cat}.com`,
      gpsLat: lat + 0.0012,
      gpsLng: lng - 0.0008,
      distanceMeters: 140,
    },
    {
      placeId: "mock-place-2",
      businessName: `Corner ${cat.charAt(0).toUpperCase() + cat.slice(1)} Express`,
      businessCategory: cat,
      contactPhone: "+1 (555) 014-9988",
      contactEmail: `contact@cornerexpress-${cat}.com`,
      gpsLat: lat - 0.0007,
      gpsLng: lng + 0.0015,
      distanceMeters: 185,
    },
    {
      placeId: "mock-place-3",
      businessName: `Pioneer ${cat.charAt(0).toUpperCase() + cat.slice(1)} Hub`,
      businessCategory: cat,
      contactPhone: "+1 (555) 011-3444",
      contactEmail: `sales@pioneerhub-${cat}.com`,
      gpsLat: lat + 0.0025,
      gpsLng: lng + 0.0021,
      distanceMeters: 310,
    },
  ];
};

export const getNearbyLeads = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const latStr = req.query.lat as string;
  const lngStr = req.query.lng as string;
  const category = (req.query.category as string || "retail_store").toLowerCase();

  if (!latStr || !lngStr) {
    res.status(400).json({ error: "lat and lng query parameters are required." });
    return;
  }

  const lat = parseFloat(latStr);
  const lng = parseFloat(lngStr);

  const apiKey = process.env.GOOGLE_MAPS_API_KEY;

  // If Google Maps API key is not valid or left as placeholder, return robust mocked data
  if (!apiKey || apiKey === "AIzaSyYourKeyHere") {
    const mockData = getMockNearbyLeads(lat, lng, category);
    res.status(200).json({ leads: mockData, source: "mock" });
    return;
  }

  try {
    // Call Google Places API Nearby Search
    // Mapping our category labels to Google Places types
    let googleType = "store";
    if (category.includes("supermarket")) googleType = "supermarket";
    else if (category.includes("restaurant")) googleType = "restaurant";
    else if (category.includes("pharmacy")) googleType = "pharmacy";

    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=1500&type=${googleType}&key=${apiKey}`;
    const response = await axios.get(url);

    if (response.data.status !== "OK" && response.data.status !== "ZERO_RESULTS") {
      throw new Error(`Google Places API returned status: ${response.data.status}`);
    }

    const googleResults = response.data.results || [];
    const leads = googleResults.map((place: any, idx: number) => ({
      placeId: place.place_id,
      businessName: place.name,
      businessCategory: googleType,
      contactPhone: place.formatted_phone_number || "",
      contactEmail: "",
      gpsLat: place.geometry.location.lat,
      gpsLng: place.geometry.location.lng,
      distanceMeters: Math.floor(
        Math.sqrt(
          Math.pow((place.geometry.location.lat - lat) * 111000, 2) +
            Math.pow((place.geometry.location.lng - lng) * 111000 * Math.cos(lat * Math.PI / 180), 2)
        )
      ),
    }));

    res.status(200).json({ leads, source: "google" });
  } catch (error: any) {
    console.warn("Google Places failed, returning mock fallback.", error.message);
    const mockData = getMockNearbyLeads(lat, lng, category);
    res.status(200).json({ leads: mockData, source: "mock_fallback" });
  }
};

export const saveLead = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { businessName, businessCategory, contactPhone, contactEmail, gpsLat, gpsLng } = req.body;

  if (!userId || !businessName || !businessCategory || gpsLat === undefined || gpsLng === undefined) {
    res.status(400).json({
      error: "businessName, businessCategory, gpsLat, and gpsLng are required.",
    });
    return;
  }

  try {
    const lead = await prisma.lead.create({
      data: {
        userId,
        businessName,
        businessCategory,
        contactPhone,
        contactEmail,
        gpsLat: Number(gpsLat),
        gpsLng: Number(gpsLng),
        leadStatus: LeadStatus.NEW,
      },
    });

    res.status(201).json({
      message: "Lead saved successfully",
      lead,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const updateLead = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const leadId = req.params.leadId as string;
  const { leadStatus, businessName, businessCategory, contactPhone, contactEmail } = req.body;

  try {
    const lead = await prisma.lead.findUnique({
      where: { id: leadId },
    });

    if (!lead) {
      res.status(404).json({ error: "Lead not found." });
      return;
    }

    if (leadStatus && !Object.values(LeadStatus).includes(leadStatus)) {
      res.status(400).json({ error: `Invalid status. Must be one of: ${Object.values(LeadStatus).join(", ")}` });
      return;
    }

    const updatedLead = await prisma.lead.update({
      where: { id: leadId },
      data: {
        leadStatus: leadStatus ? (leadStatus as LeadStatus) : undefined,
        businessName,
        businessCategory,
        contactPhone,
        contactEmail,
      },
    });

    res.status(200).json({
      message: "Lead updated successfully",
      lead: updatedLead,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const convertLeadToOutlet = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const leadId = req.params.leadId as string;

  try {
    const lead = await prisma.lead.findUnique({
      where: { id: leadId },
    });

    if (!lead) {
      res.status(404).json({ error: "Lead not found." });
      return;
    }

    if (lead.leadStatus === LeadStatus.CONVERTED) {
      res.status(400).json({ error: "Lead has already been converted to an outlet." });
      return;
    }

    const addressFromBody =
      typeof req.body?.address === "string" && req.body.address.trim()
        ? req.body.address.trim()
        : `${lead.businessName} (${lead.businessCategory})`;

    // 1. Create a new outlet record
    const outlet = await prisma.outlet.create({
      data: {
        name: lead.businessName,
        address: addressFromBody,
        contactPhone: lead.contactPhone,
        contactEmail: lead.contactEmail,
        gpsLat: lead.gpsLat,
        gpsLng: lead.gpsLng,
      },
    });

    // 2. Link lead to convertedOutletId and set status to CONVERTED
    const updatedLead = await prisma.lead.update({
      where: { id: leadId },
      data: {
        leadStatus: LeadStatus.CONVERTED,
        convertedOutletId: outlet.id,
      },
    });

    res.status(200).json({
      message: "Lead successfully converted to an outlet!",
      lead: updatedLead,
      outlet,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getLeads = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;

  try {
    const leads = await prisma.lead.findMany({
      where: {
        userId: req.user?.role === Role.SALES_EXECUTIVE ? userId : undefined,
      },
      orderBy: { createdAt: "desc" },
    });

    res.status(200).json({ leads });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
