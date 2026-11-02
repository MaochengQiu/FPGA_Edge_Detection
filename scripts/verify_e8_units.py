from pathlib import Path
import json,re,shutil
import run_tests as sim

ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'sim/build_e8_units';BUILD.mkdir(parents=True,exist_ok=True)
sim.BUILD=BUILD
REF=ROOT/'sim/reference/e7_resource'

def main():
    gamma=(REF/'gamma_correction_e7.v').read_text().replace('module gamma_correction','module gamma_correction_e7')
    (BUILD/'gamma_correction_e7.v').write_text(gamma)
    delay=(REF/'img_delay.sv').read_text().replace('module img_delay #','module img_delay_e7 #')
    (BUILD/'img_delay_e7.sv').write_text(delay)
    sim.TB_RTL['tb_e8_delay']=[str(BUILD/'img_delay_e7.sv')]
    sim.TB_RTL['tb_e8_gamma']=['rtl/gamma_conrrection/gamma_correction.v',str(BUILD/'gamma_correction_e7.v'),str(REF/'true_dual_port_ram_e7.v')]
    results=[]
    cases=[(1,0),(8,1),(3,2),(24,16),(4,2048),(8,2049),(39,2050),
        (4,2203),(42,2205),(24,4097),(8,4098),(8,4404),(4,4432),(39,4432),(24,6621),(24,13261)]
    for bits,cycles in cases:
        sim.run('tb_e8_delay',dict(BITS=bits,CYCLES=cycles))
        label=f'delay_{bits}_{cycles}'
        shutil.copy2(BUILD/'tb_e8_delay_run.log',ROOT/f'reports/e8_{label}.log')
        results.append(dict(test=label,status='PASS'))
    for width,curve in ((8,'2P2.mem'),(10,'2P2.mem'),(8,'2P0.mem')):
        shutil.copy2(ROOT/'rtl/gamma_conrrection'/curve,BUILD/'gamma.mem')
        sim.run('tb_e8_gamma',dict(DATA_WIDTH=width))
        label=f'gamma_{width}_{curve}'
        shutil.copy2(BUILD/'tb_e8_gamma_run.log',ROOT/f'reports/e8_{label}.log')
        results.append(dict(test=label,status='PASS'))
    (ROOT/'reports/e8_unit_verification.json').write_text(json.dumps(dict(status='PASS',tests=results,
        gamma_startup='Control and new ROM checked from first cycle. Compare old RGB only where defined; require full equality after initial 1032-cycle table fill, including later resets.'),indent=2))
    print('E8 UNIT PASS:',len(results),'delay-bank and gamma equivalence configurations')

if __name__=='__main__':main()
