'use client'

import { ElementType, useMemo } from 'react'
import { Fusion } from '@serverbee/types'
import { Badge, Color } from '@tremor/react'
import { Wifi } from 'lucide-react'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { StoreProvider } from '@/app/dashboard/store'

import { CpuActivity } from './components/activity/cpu'
import { NetworkActivity } from './components/activity/network'
import DiskTabView from './components/tab/disk'
import NetworkTabView from './components/tab/network'
import ProcessDetail from './components/tab/process/detail'
import ProcessList from './components/tab/process/list/page'
import CpuWidget from './components/widget/cpu'
import { DiskWidget } from './components/widget/disk'
import { MemoryWidget } from './components/widget/memory'
import NetworkWidget from './components/widget/network'
import { OsWidget } from './components/widget/os'

export default function DashboardContent({ fusion }: { fusion?: Fusion }) {
    const os = useMemo(() => fusion?.os, [fusion])

    const statusText: [ElementType, Color, string] = useMemo(() => {
        return [Wifi, 'green', 'Connected']
    }, [])

    return (
        <StoreProvider fusion={fusion}>
            <div className="flex items-center justify-between space-y-2">
                <h2 className="text-3xl font-bold tracking-tight">
                    {os?.name ?? 'Unknown'}
                </h2>
                <Badge size="md" icon={statusText[0]} color={statusText[1]}>
                    {statusText[2]}
                </Badge>
            </div>
            <Tabs
                defaultValue="overview"
                className="mt-3 space-y-4"
                onValueChange={(value) => {}}
            >
                <TabsList>
                    <TabsTrigger value="overview">Overview</TabsTrigger>
                    <TabsTrigger value="process">Process</TabsTrigger>
                    <TabsTrigger value="detail">Disk & Network</TabsTrigger>
                </TabsList>
                <TabsContent value="overview" className="space-y-4">
                    <OsWidget className="ml-1" />
                    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                        <CpuWidget />
                        <MemoryWidget />
                        <NetworkWidget />
                        <DiskWidget />
                    </div>
                    <div className="grid grid-cols-1 gap-y-4 md:grid-cols-2 lg:grid-cols-7 lg:gap-x-4">
                        <Card className="col-span-3">
                            <CardHeader>
                                <CardTitle>CPU Activity</CardTitle>
                            </CardHeader>
                            <CardContent className="px-2 pb-4">
                                <CpuActivity />
                            </CardContent>
                        </Card>
                        <Card className="col-span-4">
                            <CardHeader>
                                <CardTitle>Network Activity</CardTitle>
                            </CardHeader>
                            <CardContent className="px-2 pb-4">
                                <NetworkActivity />
                            </CardContent>
                        </Card>
                    </div>
                </TabsContent>
                <TabsContent value="process" className="space-y-4">
                    <div className="grid grid-cols-1 gap-y-4 md:grid-cols-2 lg:grid-cols-7 lg:gap-x-4">
                        <div className="col-span-3">{<ProcessList />}</div>
                        <div className="col-span-4">{<ProcessDetail />}</div>
                    </div>
                </TabsContent>
                <TabsContent value="detail" className="space-y-4">
                    <div className="grid grid-cols-1 gap-y-4 md:grid-cols-2 lg:grid-cols-7 lg:gap-x-4">
                        <div className="col-span-3">{<DiskTabView />}</div>
                        <div className="col-span-4">{<NetworkTabView />}</div>
                    </div>
                </TabsContent>
            </Tabs>
        </StoreProvider>
    )
}
