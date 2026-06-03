using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace BlitztextWin.App.Services;

public sealed class WavAudioRecorder : IDisposable
{
    private const int WaveMapper = -1;
    private const int CallbackFunction = 0x00030000;
    private const int WimData = 0x3C0;
    private const ushort WaveFormatPcm = 1;
    private const int SampleRate = 16000;
    private const ushort Channels = 1;
    private const ushort BitsPerSample = 16;
    private const int BufferCount = 4;
    private const int BufferMilliseconds = 120;

    private readonly object sync = new();
    private readonly MemoryStream audioData = new();
    private readonly WaveInProc callback;
    private readonly List<BufferState> buffers = [];
    private readonly Stopwatch stopwatch = new();

    private IntPtr waveInHandle;
    private bool isRecording;
    private string? currentFilePath;

    public WavAudioRecorder()
    {
        callback = WaveInCallback;
    }

    public string Start()
    {
        if (isRecording)
        {
            throw new InvalidOperationException("Aufnahme laeuft bereits.");
        }

        audioData.SetLength(0);
        currentFilePath = Path.Combine(Path.GetTempPath(), "blitztext-" + Guid.NewGuid().ToString("N") + ".wav");

        var format = new WaveFormat
        {
            FormatTag = WaveFormatPcm,
            Channels = Channels,
            SamplesPerSec = SampleRate,
            BitsPerSample = BitsPerSample,
            BlockAlign = (ushort)(Channels * BitsPerSample / 8),
            AvgBytesPerSec = SampleRate * Channels * BitsPerSample / 8,
            Size = 0,
        };

        var result = waveInOpen(out waveInHandle, WaveMapper, ref format, callback, IntPtr.Zero, CallbackFunction);
        if (result != 0)
        {
            throw new InvalidOperationException("Mikrofon konnte nicht geoeffnet werden. Fehlercode: " + result);
        }

        AllocateBuffers();
        foreach (var buffer in buffers)
        {
            Check(waveInPrepareHeader(waveInHandle, buffer.HeaderPointer, Marshal.SizeOf<WaveHeader>()));
            Check(waveInAddBuffer(waveInHandle, buffer.HeaderPointer, Marshal.SizeOf<WaveHeader>()));
        }

        isRecording = true;
        stopwatch.Restart();
        Check(waveInStart(waveInHandle));
        return currentFilePath;
    }

    public RecordedAudio Stop()
    {
        if (!isRecording || currentFilePath is null)
        {
            throw new InvalidOperationException("Es laeuft keine Aufnahme.");
        }

        isRecording = false;
        stopwatch.Stop();
        waveInStop(waveInHandle);
        waveInReset(waveInHandle);

        foreach (var buffer in buffers)
        {
            waveInUnprepareHeader(waveInHandle, buffer.HeaderPointer, Marshal.SizeOf<WaveHeader>());
            buffer.Dispose();
        }

        buffers.Clear();
        waveInClose(waveInHandle);
        waveInHandle = IntPtr.Zero;

        byte[] data;
        lock (sync)
        {
            data = audioData.ToArray();
        }

        WriteWaveFile(currentFilePath, data);
        return new RecordedAudio(currentFilePath, stopwatch.Elapsed);
    }

    private void AllocateBuffers()
    {
        var bytesPerSample = Channels * BitsPerSample / 8;
        var bufferSize = SampleRate * bytesPerSample * BufferMilliseconds / 1000;

        for (var index = 0; index < BufferCount; index++)
        {
            var bufferPointer = Marshal.AllocHGlobal(bufferSize);
            var header = new WaveHeader
            {
                Data = bufferPointer,
                BufferLength = (uint)bufferSize,
            };
            var headerPointer = Marshal.AllocHGlobal(Marshal.SizeOf<WaveHeader>());
            Marshal.StructureToPtr(header, headerPointer, false);
            buffers.Add(new BufferState(bufferPointer, headerPointer));
        }
    }

    private void WaveInCallback(IntPtr handle, uint message, IntPtr instance, IntPtr parameter1, IntPtr parameter2)
    {
        if (message != WimData || parameter1 == IntPtr.Zero)
        {
            return;
        }

        var header = Marshal.PtrToStructure<WaveHeader>(parameter1);
        if (header.BytesRecorded > 0)
        {
            var data = new byte[header.BytesRecorded];
            Marshal.Copy(header.Data, data, 0, data.Length);
            lock (sync)
            {
                audioData.Write(data, 0, data.Length);
            }
        }

        if (isRecording)
        {
            waveInAddBuffer(handle, parameter1, Marshal.SizeOf<WaveHeader>());
        }
    }

    private static void WriteWaveFile(string path, byte[] pcmData)
    {
        using var file = File.Create(path);
        using var writer = new BinaryWriter(file);
        var byteRate = SampleRate * Channels * BitsPerSample / 8;
        var blockAlign = Channels * BitsPerSample / 8;

        writer.Write("RIFF"u8);
        writer.Write(36 + pcmData.Length);
        writer.Write("WAVE"u8);
        writer.Write("fmt "u8);
        writer.Write(16);
        writer.Write(WaveFormatPcm);
        writer.Write((ushort)Channels);
        writer.Write(SampleRate);
        writer.Write(byteRate);
        writer.Write((ushort)blockAlign);
        writer.Write((ushort)BitsPerSample);
        writer.Write("data"u8);
        writer.Write(pcmData.Length);
        writer.Write(pcmData);
    }

    private static void Check(uint result)
    {
        if (result != 0)
        {
            throw new InvalidOperationException("Windows-Audiofehler: " + result);
        }
    }

    public void Dispose()
    {
        if (isRecording)
        {
            try
            {
                Stop();
            }
            catch (InvalidOperationException)
            {
            }
        }

        audioData.Dispose();
    }

    [DllImport("winmm.dll")]
    private static extern uint waveInOpen(out IntPtr waveInHandle, int deviceId, ref WaveFormat format, WaveInProc callback, IntPtr instance, int flags);

    [DllImport("winmm.dll")]
    private static extern uint waveInPrepareHeader(IntPtr waveInHandle, IntPtr header, int headerSize);

    [DllImport("winmm.dll")]
    private static extern uint waveInUnprepareHeader(IntPtr waveInHandle, IntPtr header, int headerSize);

    [DllImport("winmm.dll")]
    private static extern uint waveInAddBuffer(IntPtr waveInHandle, IntPtr header, int headerSize);

    [DllImport("winmm.dll")]
    private static extern uint waveInStart(IntPtr waveInHandle);

    [DllImport("winmm.dll")]
    private static extern uint waveInStop(IntPtr waveInHandle);

    [DllImport("winmm.dll")]
    private static extern uint waveInReset(IntPtr waveInHandle);

    [DllImport("winmm.dll")]
    private static extern uint waveInClose(IntPtr waveInHandle);

    private delegate void WaveInProc(IntPtr handle, uint message, IntPtr instance, IntPtr parameter1, IntPtr parameter2);

    [StructLayout(LayoutKind.Sequential)]
    private struct WaveFormat
    {
        public ushort FormatTag;
        public ushort Channels;
        public int SamplesPerSec;
        public int AvgBytesPerSec;
        public ushort BlockAlign;
        public ushort BitsPerSample;
        public ushort Size;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WaveHeader
    {
        public IntPtr Data;
        public uint BufferLength;
        public uint BytesRecorded;
        public IntPtr User;
        public uint Flags;
        public uint Loops;
        public IntPtr Next;
        public IntPtr Reserved;
    }

    private sealed class BufferState(IntPtr dataPointer, IntPtr headerPointer) : IDisposable
    {
        public IntPtr HeaderPointer { get; } = headerPointer;

        public void Dispose()
        {
            Marshal.FreeHGlobal(HeaderPointer);
            Marshal.FreeHGlobal(dataPointer);
        }
    }
}

public sealed record RecordedAudio(string FilePath, TimeSpan Duration);
